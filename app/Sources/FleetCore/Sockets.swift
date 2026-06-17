import Darwin
import Foundation

// Native socket inspection via proc_pidfdinfo — replaces lsof.
// Listening TCP ports + unix-socket peer pairing (soi_so ↔ unsi_conn_so),
// the native equivalent of lsof's device↔peer trick.

private let kListFDs: Int32 = 1        // PROC_PIDLISTFDS
private let kFDSocket: Int32 = 3       // PROC_PIDFDSOCKETINFO
private let kFDTypeSocket: UInt32 = 2  // PROX_FDTYPE_SOCKET
private let kSockTCP: Int32 = 2        // SOCKINFO_TCP
private let kSockUN: Int32 = 3         // SOCKINFO_UN
private let tcpLISTEN: Int32 = 1       // TCPS_LISTEN
private let tcpESTAB: Int32 = 4        // TCPS_ESTABLISHED

struct SockData {
    var ports: [Int32: [PortInfo]] = [:]
    var unixListen: [Int32: [String]] = [:]
    var unixEPs: [(pid: Int32, so: UInt64, peer: UInt64)] = []
    var tcpEPs: [(pid: Int32, local: String, remote: String)] = []
}

extension Collector {
    func scanSockets(_ pids: [Int32]) -> SockData {
        var d = SockData()
        for pid in pids {
            let bufSize = proc_pidinfo(pid, kListFDs, 0, nil, 0)
            guard bufSize > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(),
                                    count: Int(bufSize) / MemoryLayout<proc_fdinfo>.stride)
            let r = proc_pidinfo(pid, kListFDs, 0, &fds, bufSize)
            guard r > 0 else { continue }
            let count = Int(r) / MemoryLayout<proc_fdinfo>.stride

            for i in 0..<count {
                guard fds[i].proc_fdtype == kFDTypeSocket else { continue }
                var si = socket_fdinfo()
                let ssz = Int32(MemoryLayout<socket_fdinfo>.size)
                guard proc_pidfdinfo(pid, fds[i].proc_fd, kFDSocket, &si, ssz) == ssz else { continue }
                let psi = si.psi

                switch psi.soi_kind {
                case kSockTCP:
                    let ini = psi.soi_proto.pri_tcp.tcpsi_ini
                    let state = psi.soi_proto.pri_tcp.tcpsi_state
                    if state == tcpLISTEN {
                        let lport = port16(ini.insi_lport)
                        if lport > 0 {
                            d.ports[pid, default: []].append(
                                PortInfo(port: Int(lport), proto: "tcp", scope: scope(ini)))
                        }
                    } else if state == tcpESTAB {
                        d.tcpEPs.append((pid, ipPort(ini, local: true), ipPort(ini, local: false)))
                    }
                case kSockUN:
                    let un = psi.soi_proto.pri_un
                    if un.unsi_conn_so != 0 {
                        d.unixEPs.append((pid, psi.soi_so, un.unsi_conn_so))
                    }
                    let path = sunPath(un)
                    if !path.isEmpty { d.unixListen[pid, default: []].append(path) }
                default:
                    break
                }
            }
        }
        return d
    }
}

// network-order 16-bit port → host order
private func port16(_ v: Int32) -> UInt16 { UInt16(truncatingIfNeeded: v).byteSwapped }

private func scope(_ ini: in_sockinfo) -> String {
    if ini.insi_vflag & 0x2 != 0 { // IPv6
        var a = ini.insi_laddr.ina_6
        let bytes = withUnsafeBytes(of: &a) { Array($0) }
        if bytes.allSatisfy({ $0 == 0 }) { return "all" }                       // ::
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return "localhost" } // ::1
        return "all"
    }
    let s = ini.insi_laddr.ina_46.i46a_addr4.s_addr   // network order
    if s == 0 { return "all" }                          // 0.0.0.0
    if s == 0x0100_007f { return "localhost" }          // 127.0.0.1
    return "all"
}

private func ipPort(_ ini: in_sockinfo, local: Bool) -> String {
    let p = port16(local ? ini.insi_lport : ini.insi_fport)
    if ini.insi_vflag & 0x2 != 0 {
        var a = local ? ini.insi_laddr.ina_6 : ini.insi_faddr.ina_6
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &a, &buf, socklen_t(INET6_ADDRSTRLEN))
        return "[\(String(cString: buf))]:\(p)"
    }
    var a = local ? ini.insi_laddr.ina_46.i46a_addr4 : ini.insi_faddr.ina_46.i46a_addr4
    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
    return "\(String(cString: buf)):\(p)"
}

// sockaddr_un layout: sun_len(1) sun_family(1) sun_path[104] — read path at offset 2
private func sunPath(_ un: un_sockinfo) -> String {
    var u = un
    return withUnsafeBytes(of: &u.unsi_addr) { raw -> String in
        guard raw.count > 2 else { return "" }
        let base = raw.baseAddress!.advanced(by: 2).assumingMemoryBound(to: CChar.self)
        return String(cString: base)
    }
}
