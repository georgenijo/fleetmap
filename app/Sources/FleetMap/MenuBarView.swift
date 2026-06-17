import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: SnapshotStore
    @Environment(\.openWindow) private var openWindow

    var top: [RowItem] { Array(makeRows(store.snapshot).prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("fleetmap").font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.0f%% · %.1f GB", store.totalCPU, store.totalRAMGB))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            Divider()

            ForEach(top) { r in
                HStack(spacing: 8) {
                    Circle().fill(cpuColor(r.cpu)).frame(width: 6, height: 6)
                    Text(r.label).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%%", r.cpu)).monospacedDigit()
                        .foregroundStyle(.secondary).font(.caption)
                }
                .padding(.horizontal, 12).padding(.vertical, 3)
            }

            Divider().padding(.top, 4)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open fleetmap", systemImage: "macwindow")
            }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 10)
        }
        .frame(width: 280)
    }
}
