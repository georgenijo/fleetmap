import SwiftUI
import FleetCore

// CPU heat: green (idle) → amber → red (hot). Matches the graph view.
func cpuColor(_ cpu: Double) -> Color {
    let c = min(max(cpu, 0), 100) / 100
    return Color(hue: 0.34 * (1 - c), saturation: 0.78, brightness: 0.92)
}

func fmtMB(_ v: Double) -> String {
    v >= 1024 ? String(format: "%.1f GB", v / 1024) : String(format: "%.0f MB", v)
}

enum Pane: String, CaseIterable, Identifiable {
    case list, graph
    var id: String { rawValue }
    var title: String { self == .list ? "List" : "Graph" }
    var icon: String { self == .list ? "list.bullet" : "point.3.connected.trianglepath.dotted" }
}

// One flattened row for the native Table (a node, or a child process under it).
struct RowItem: Identifiable {
    let id: String
    let label: String
    let kind: String      // app | proc | child
    let cpu: Double
    let rss: Double
    let procs: Int
    let ports: [PortInfo]
    let conns: Int
    let cmd: String
    var children: [RowItem]?
}

func makeRows(_ snap: Snapshot) -> [RowItem] {
    var conns: [String: Int] = [:]
    for e in snap.edges { conns[e.src, default: 0] += 1; conns[e.dst, default: 0] += 1 }
    return snap.nodes.map { n in
        let kids: [RowItem]? = n.children.count > 1 ? n.children.map { c in
            RowItem(id: "\(n.id)#\(c.pid)", label: "\(c.label)  #\(c.pid)", kind: "child",
                    cpu: c.cpu, rss: c.rss_mb, procs: 1, ports: [], conns: 0, cmd: c.cmd, children: nil)
        } : nil
        return RowItem(id: n.id, label: n.label, kind: n.kind, cpu: n.cpu, rss: n.rss_mb,
                       procs: n.pids.count, ports: n.ports, conns: conns[n.id] ?? 0,
                       cmd: n.cmd, children: kids)
    }
}
