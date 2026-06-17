import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SnapshotStore
    @State private var pane: Pane = .list

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(pane: $pane)
            Divider().opacity(0.4)
            switch pane {
            case .list:  ListView()
            case .graph: GraphView()
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(BackgroundView())
    }
}

struct HeaderBar: View {
    @EnvironmentObject var store: SnapshotStore
    @Binding var pane: Pane
    @AppStorage("menuBarVisible") private var menuBarVisible = true

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.tint)
                Text("fleetmap").font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { p in
                    Label(p.title, systemImage: p.icon).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            Spacer()

            stat("\(store.snapshot.nodes.count)", "nodes")
            stat(String(format: "%.0f%%", store.totalCPU), "cpu")
            if store.totalGPU > 0 {
                stat(String(format: "%.0f%%", store.totalGPU), "gpu")
                    .help("system-wide GPU utilization")
            }
            stat(String(format: "%.1f GB", store.totalRAMGB), "ram")
            if store.skipped > 0 {
                stat("\(store.skipped)", "hidden")
                    .help("processes owned by other users — run privileged for full coverage")
            }

            Divider().frame(height: 22).padding(.horizontal, 2)

            Button { menuBarVisible.toggle() } label: {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 14))
                    .foregroundStyle(menuBarVisible ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(menuBarVisible ? "Hide the menu-bar readout" : "Show the menu-bar readout")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).textCase(.uppercase)
        }
    }
}

// translucent window background (vibrancy)
struct BackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

