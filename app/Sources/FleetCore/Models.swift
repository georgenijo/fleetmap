import Foundation

// Wire model — mirrors the Go tool's snapshot contract so the WKWebView graph
// (which speaks the same JSON) can consume it unchanged.
// NB: named PortInfo, not Port, to avoid colliding with Foundation's NSPort→Port.

public struct PortInfo: Codable, Sendable, Hashable {
    public var port: Int
    public var proto: String   // tcp
    public var scope: String   // localhost | all
    public init(port: Int, proto: String, scope: String) {
        self.port = port; self.proto = proto; self.scope = scope
    }
}

public struct Child: Codable, Sendable {
    public var pid: Int
    public var label: String
    public var cpu: Double
    public var gpu: Double
    public var rss_mb: Double
    public var cmd: String
    public init(pid: Int, label: String, cpu: Double, gpu: Double, rss_mb: Double, cmd: String) {
        self.pid = pid; self.label = label; self.cpu = cpu; self.gpu = gpu; self.rss_mb = rss_mb; self.cmd = cmd
    }
}

public struct Node: Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var kind: String    // app | proc
    public var cpu: Double
    public var gpu: Double
    public var rss_mb: Double
    public var pids: [Int]
    public var ports: [PortInfo]
    public var sockets: [String]
    public var cmd: String
    public var children: [Child]
    public init(id: String, label: String, kind: String, cpu: Double, gpu: Double, rss_mb: Double,
                pids: [Int], ports: [PortInfo], sockets: [String], cmd: String, children: [Child]) {
        self.id = id; self.label = label; self.kind = kind; self.cpu = cpu; self.gpu = gpu; self.rss_mb = rss_mb
        self.pids = pids; self.ports = ports; self.sockets = sockets; self.cmd = cmd; self.children = children
    }
}

public struct NetIface: Codable, Sendable, Identifiable {
    public var name: String
    public var rx_bps: Double
    public var tx_bps: Double
    public var id: String { name }
    public init(name: String, rx_bps: Double, tx_bps: Double) {
        self.name = name; self.rx_bps = rx_bps; self.tx_bps = tx_bps
    }
}

public struct Edge: Codable, Sendable {
    public var src: String
    public var dst: String
    public var kind: String    // unix | tcp
    public var detail: String
    public init(src: String, dst: String, kind: String, detail: String) {
        self.src = src; self.dst = dst; self.kind = kind; self.detail = detail
    }
}

public struct Snapshot: Codable, Sendable {
    public var ts: Int64
    public var nodes: [Node]
    public var edges: [Edge]
    public var gpu_util: Double   // system-wide GPU busy %, 0 if unavailable (Intel)
    public var soc_temp: Double   // average active-die SoC temp °C, 0 if unavailable
    public var net_rx_bps: Double // system-wide download bytes/sec
    public var net_tx_bps: Double // system-wide upload bytes/sec
    public var net_ifaces: [NetIface] // per-interface rates (for the LAN dropdown)
    public var note: String?
    public init(ts: Int64, nodes: [Node], edges: [Edge], gpu_util: Double = 0,
                soc_temp: Double = 0, net_rx_bps: Double = 0, net_tx_bps: Double = 0,
                net_ifaces: [NetIface] = [], note: String?) {
        self.ts = ts; self.nodes = nodes; self.edges = edges; self.gpu_util = gpu_util
        self.soc_temp = soc_temp; self.net_rx_bps = net_rx_bps; self.net_tx_bps = net_tx_bps
        self.net_ifaces = net_ifaces; self.note = note
    }
}
