import Darwin
import Foundation

// proc_info flavors / constants not always surfaced as Swift symbols.
private let kAllPIDs: UInt32 = 1            // PROC_ALL_PIDS
private let kTaskInfo: Int32 = 4           // PROC_PIDTASKINFO
private let kTBSDInfo: Int32 = 3           // PROC_PIDTBSDINFO
private let kPathMax: UInt32 = 4096        // PROC_PIDPATHINFO_MAXSIZE

// One raw per-process reading.
struct Reading {
    var pid: Int32
    var ppid: Int32
    var cpuNS: UInt64        // cumulative user+system, nanoseconds
    var rssBytes: UInt64
    var path: String
    var comm: String         // kernel short name (fallback for pathless procs)
}

public final class Collector {
    private var prevCPU: [Int32: UInt64] = [:]
    private var prevWall: UInt64 = 0
    public let minCPU: Double
    public let minMB: Double

    public init(minCPU: Double = 0.5, minMB: Double = 40) {
        self.minCPU = minCPU
        self.minMB = minMB
    }

    public func collect() -> Snapshot {
        let readings = sample()
        let wall = monotonicNS()
        let wallDelta = prevWall == 0 ? 0 : wall &- prevWall

        // per-pid CPU% from the delta vs the previous sample
        var cpuPct: [Int32: Double] = [:]
        for r in readings {
            if let prev = prevCPU[r.pid], wallDelta > 0, r.cpuNS >= prev {
                cpuPct[r.pid] = Double(r.cpuNS - prev) / Double(wallDelta) * 100.0
            } else {
                cpuPct[r.pid] = 0
            }
        }
        prevCPU = Dictionary(readings.map { ($0.pid, $0.cpuNS) }, uniquingKeysWith: { a, _ in a })
        prevWall = wall

        let sock = scanSockets(readings.map { $0.pid })
        let (nodes, pidToNode) = buildNodes(readings, cpu: cpuPct, sock: sock)
        let visible = Set(nodes.map { $0.id })
        let edges = buildEdges(sock, pidToNode: pidToNode, visible: visible)
        return Snapshot(ts: Int64(Date().timeIntervalSince1970), nodes: nodes, edges: edges, note: nil)
    }

    // ---- libproc sampling ----

    public private(set) var lastSkipped = 0
    public private(set) var lastSeen = 0

    private func sample() -> [Reading] {
        let n = proc_listpids(kAllPIDs, 0, nil, 0)
        guard n > 0 else { return [] }
        let cap = Int(n) / MemoryLayout<Int32>.stride
        var pids = [Int32](repeating: 0, count: cap)
        let n2 = proc_listpids(kAllPIDs, 0, &pids, n)
        guard n2 > 0 else { return [] }
        let count = Int(n2) / MemoryLayout<Int32>.stride

        var out: [Reading] = []
        out.reserveCapacity(count)
        var skipped = 0, seen = 0
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            seen += 1
            guard let ti = taskInfo(pid) else { skipped += 1; continue }   // can't read (other uid)
            let (ppid, comm) = bsdInfo(pid)
            out.append(Reading(
                pid: pid,
                ppid: ppid,
                cpuNS: ti.pti_total_user &+ ti.pti_total_system,
                rssBytes: ti.pti_resident_size,
                path: procPath(pid),
                comm: comm))
        }
        lastSkipped = skipped
        lastSeen = seen
        return out
    }

    // pti_total_user/system are in mach absolute-time units, NOT nanoseconds.
    // Sampling the wall clock in the same units (mach_absolute_time) makes the
    // timebase cancel out, so cpuDelta/wallDelta is a correct fraction.
    private func monotonicNS() -> UInt64 { mach_absolute_time() }

    private func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var ti = proc_taskinfo()
        let sz = Int32(MemoryLayout<proc_taskinfo>.size)
        let r = proc_pidinfo(pid, kTaskInfo, 0, &ti, sz)
        return r == sz ? ti : nil
    }

    private func bsdInfo(_ pid: Int32) -> (Int32, String) {
        var bi = proc_bsdinfo()
        let sz = Int32(MemoryLayout<proc_bsdinfo>.size)
        let r = proc_pidinfo(pid, kTBSDInfo, 0, &bi, sz)
        guard r == sz else { return (0, "") }
        let comm = withUnsafeBytes(of: bi.pbi_comm) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return (Int32(bitPattern: bi.pbi_ppid), comm)
    }

    private func procPath(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: Int(kPathMax))
        let r = proc_pidpath(pid, &buf, kPathMax)
        return r > 0 ? String(cString: buf) : ""
    }

    // ---- aggregate readings into grouped nodes ----

    private func buildNodes(_ readings: [Reading], cpu: [Int32: Double], sock: SockData) -> ([Node], [Int32: String]) {
        var byID: [String: Node] = [:]
        var order: [String] = []
        var pidToNode: [Int32: String] = [:]

        for r in readings {
            let exe = r.path.isEmpty ? r.comm : r.path
            let (id, label, kind) = identify(exe: exe, comm: r.comm)
            pidToNode[r.pid] = id
            let cpuV = cpu[r.pid] ?? 0
            let rssMB = Double(r.rssBytes) / 1_048_576.0
            let cmd = redact(exe)

            if byID[id] == nil {
                byID[id] = Node(id: id, label: label, kind: kind, cpu: 0, rss_mb: 0,
                                pids: [], ports: [], sockets: [], cmd: cmd, children: [])
                order.append(id)
            }
            byID[id]!.cpu += cpuV
            byID[id]!.rss_mb += rssMB
            byID[id]!.pids.append(Int(r.pid))
            byID[id]!.children.append(Child(
                pid: Int(r.pid), label: baseName(exe), cpu: round1(cpuV),
                rss_mb: round1(rssMB), cmd: cmd))
            if let ps = sock.ports[r.pid] { byID[id]!.ports.append(contentsOf: ps) }
            if let ss = sock.unixListen[r.pid] { byID[id]!.sockets.append(contentsOf: ss) }
        }

        var nodes: [Node] = []
        for id in order {
            var n = byID[id]!
            n.cpu = round1(n.cpu)
            n.rss_mb = round1(n.rss_mb)
            n.pids.sort()
            n.ports = dedupPorts(n.ports)
            n.sockets = Array(Set(n.sockets)).sorted()
            n.children.sort { $0.cpu > $1.cpu }
            // keep only meaningful services
            if n.cpu >= minCPU || n.rss_mb >= minMB || !n.ports.isEmpty || !n.sockets.isEmpty {
                nodes.append(n)
            }
        }
        nodes.sort { $0.cpu > $1.cpu }
        return (nodes, pidToNode)
    }

    // ---- edges: only between visible nodes, so system IPC hubs don't hairball ----

    private func buildEdges(_ sock: SockData, pidToNode: [Int32: String], visible: Set<String>) -> [Edge] {
        var seen = Set<String>()
        var out: [Edge] = []
        func add(_ a: String, _ b: String, _ kind: String, _ detail: String) {
            guard !a.isEmpty, !b.isEmpty, a != b, visible.contains(a), visible.contains(b) else { return }
            let (x, y) = a < b ? (a, b) : (b, a)
            let key = "\(kind)|\(x)|\(y)"
            if seen.insert(key).inserted { out.append(Edge(src: x, dst: y, kind: kind, detail: detail)) }
        }

        // unix: my socket pointer ↔ peer's socket pointer
        var soToPID: [UInt64: Int32] = [:]
        for e in sock.unixEPs { soToPID[e.so] = e.pid }
        for e in sock.unixEPs where e.peer != 0 {
            if let pp = soToPID[e.peer], let a = pidToNode[e.pid], let b = pidToNode[pp] {
                add(a, b, "unix", "unix socket")
            }
        }

        // tcp: pair established endpoints local ↔ remote
        var localToPID: [String: Int32] = [:]
        for e in sock.tcpEPs { localToPID[e.local] = e.pid }
        for e in sock.tcpEPs {
            if let pp = localToPID[e.remote], let a = pidToNode[e.pid], let b = pidToNode[pp] {
                add(a, b, "tcp", "\(e.local)→\(e.remote)")
            }
        }

        return out.sorted { $0.src == $1.src ? $0.dst < $1.dst : $0.src < $1.src }
    }

    private func dedupPorts(_ ports: [PortInfo]) -> [PortInfo] {
        var seen = Set<String>()
        var out: [PortInfo] = []
        for p in ports {
            let k = "\(p.proto):\(p.port):\(p.scope)"
            if seen.insert(k).inserted { out.append(p) }
        }
        return out.sorted { $0.port < $1.port }
    }

    private func identify(exe: String, comm: String) -> (String, String, String) {
        if let (bundle, name) = appBundle(exe) {
            return ("app:" + bundle, name, "app")
        }
        let label = exe.isEmpty ? (comm.isEmpty ? "?" : comm) : baseName(exe)
        let key = "proc:" + label + ":" + String(djb2(exe))
        return (key, label, "proc")
    }
}

// ---- helpers ----

func appBundle(_ exe: String) -> (String, String)? {
    if let r = exe.range(of: ".app/") {
        let bundle = String(exe[exe.startIndex..<r.lowerBound]) + ".app"
        return (bundle, baseName(String(bundle.dropLast(4))))
    }
    if exe.hasSuffix(".app") {
        return (exe, baseName(String(exe.dropLast(4))))
    }
    return nil
}

func baseName(_ p: String) -> String {
    if p.isEmpty { return "?" }
    return (p as NSString).lastPathComponent
}

func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

func djb2(_ s: String) -> UInt32 {
    var h: UInt32 = 5381
    for b in s.utf8 { h = (h &* 33) &+ UInt32(b) }
    return h
}
