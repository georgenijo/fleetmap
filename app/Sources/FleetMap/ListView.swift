import SwiftUI
import FleetCore

struct ListView: View {
    @EnvironmentObject var store: SnapshotStore
    @State private var sort = [KeyPathComparator(\RowItem.cpu, order: .reverse)]

    var rows: [RowItem] {
        var r = makeRows(store.snapshot)
        r.sort(using: sort)
        return r
    }

    var body: some View {
        Table(of: RowItem.self, sortOrder: $sort) {
            TableColumn("Process", value: \.label) { r in
                HStack(spacing: 8) {
                    Circle().fill(cpuColor(r.cpu)).frame(width: 7, height: 7)
                        .opacity(r.kind == "child" ? 0 : 1)
                    Text(r.label)
                        .fontWeight(r.kind == "child" ? .regular : .medium)
                        .foregroundStyle(r.kind == "child" ? .secondary : .primary)
                    if r.kind == "app" {
                        Text("·\(r.procs)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .width(min: 170, ideal: 240)

            TableColumn("CPU %", value: \.cpu) { r in
                Text(String(format: "%.1f", r.cpu))
                    .font(.system(.body, design: .rounded)).monospacedDigit()
                    .foregroundStyle(r.cpu >= 1 ? .black : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1.5)
                    .background(cpuColor(r.cpu).opacity(r.cpu >= 1 ? 1 : 0),
                                in: RoundedRectangle(cornerRadius: 5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(76)

            TableColumn("RAM", value: \.rss) { r in
                Text(fmtMB(r.rss)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(82)

            TableColumn("Procs", value: \.procs) { r in
                Text(r.kind == "child" ? "" : "\(r.procs)").monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(52)

            TableColumn("Ports") { r in PortsCell(ports: r.ports) }
                .width(min: 80, ideal: 150)

            TableColumn("Conns", value: \.conns) { r in
                Text(r.conns > 0 ? "\(r.conns)" : "").monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(54)

            TableColumn("Command", value: \.cmd) { r in
                Text(r.cmd).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        } rows: {
            ForEach(rows) { r in
                if let kids = r.children {
                    DisclosureTableRow(r) { ForEach(kids) { TableRow($0) } }
                } else {
                    TableRow(r)
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
    }
}

struct PortsCell: View {
    let ports: [PortInfo]
    var body: some View {
        if ports.isEmpty {
            Text("").frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 4) {
                ForEach(ports.prefix(4), id: \.self) { p in
                    Text(":\(p.port)\(p.scope == "all" ? "⚠" : "")")
                        .font(.caption2).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            (p.scope == "all" ? Color.orange : Color.blue).opacity(0.18),
                            in: Capsule())
                        .foregroundStyle(p.scope == "all" ? .orange : .blue)
                }
                if ports.count > 4 {
                    Text("+\(ports.count - 4)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
