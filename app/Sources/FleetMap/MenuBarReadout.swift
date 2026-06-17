import SwiftUI
import AppKit
import FleetCore

// One combined NSStatusItem rendering all metrics in a single tight item — vs
// Stats' one item per metric. Each metric is a Stats-style stack: tiny label on
// top, value below. SoC keeps a yellow→red heat tint; GPU/LAN are plain.
struct MenuBarReadout: View {
    @EnvironmentObject var store: SnapshotStore

    var body: some View {
        HStack(spacing: 9) {
            metric("SoC", store.socTemp > 0 ? String(format: "%.0f°", store.socTemp) : "—",
                   tempColor(store.socTemp))
            metric("GPU", String(format: "%.0f%%", store.totalGPU), .primary)
            metric("LAN", fmtMbps(store.netRx + store.netTx), .primary)
        }
        .padding(.horizontal, 5)
        .fixedSize()
        .allowsHitTesting(false)   // clicks fall through to the status-item button
    }

    private func metric(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: -1) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

// Combined throughput in Mbps (bits/sec) — "1.9", "14".
func fmtMbps(_ bytesPerSec: Double) -> String {
    let m = bytesPerSec * 8 / 1_000_000
    return m >= 10 ? String(format: "%.0f", m) : String(format: "%.1f", m)
}

// SoC heat: neutral until warm, yellow → red past throttle territory.
func tempColor(_ c: Double) -> Color {
    switch c {
    case ..<70:   return .primary
    case 70..<90: return .yellow
    default:      return .red
    }
}

func fleetOpenMainWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    for w in NSApp.windows where w.canBecomeMain {
        w.makeKeyAndOrderFront(nil)
        return
    }
}

// ---- click dropdown: rich per-metric detail with live sparklines ----

// Filled gradient sparkline of a value history.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let range = max(hi - lo, 0.0001)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: size.height * (1 - CGFloat((values[i] - lo) / range)))
            }
            var line = Path()
            line.move(to: pt(0))
            for i in 1..<values.count { line.addLine(to: pt(i)) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), lineWidth: 1.5)
        }
    }
}

struct MenuBarDetail: View {
    @EnvironmentObject var store: SnapshotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            socSection
            gpuSection
            lanSection
            Divider()
            HStack {
                Button("Open fleetmap") { fleetOpenMainWindow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }

    // SoC — average active die, hottest sensor, top sensors (real IOHID names).
    private var socSection: some View {
        let sensors = Temp.readAll().filter { $0.c > 0 && $0.c < 130 }.sorted { $0.c > $1.c }
        return section("thermometer.medium", .red, "SoC",
                       store.socTemp > 0 ? String(format: "%.0f°", store.socTemp) : "—",
                       store.socHist) {
            if let hot = sensors.first { row("hottest", "\(hot.name)  \(Int(hot.c))°") }
            ForEach(Array(sensors.dropFirst().prefix(2)), id: \.name) { s in row(s.name, "\(Int(s.c))°") }
        }
    }

    // GPU — utilization, renderer/tiler split, top visible GPU processes.
    private var gpuSection: some View {
        let stats = GPU.deviceStats()
        let top = store.snapshot.nodes.filter { $0.gpu > 0 }.sorted { $0.gpu > $1.gpu }.prefix(3)
        return section("cpu.fill", .blue, "GPU", String(format: "%.0f%%", store.totalGPU), store.gpuHist) {
            row("render / tiler", String(format: "%.0f%% / %.0f%%", stats.renderer, stats.tiler))
            if top.isEmpty {
                row("top process", "— system GPU hidden")
            } else {
                ForEach(Array(top)) { n in row(n.label, String(format: "%.1f%%", n.gpu)) }
            }
        }
    }

    // LAN — combined + down/up, then per-interface rates.
    private var lanSection: some View {
        section("network", .green, "LAN", "\(fmtMbps(store.netRx + store.netTx)) Mbps", store.lanHist) {
            row("down / up", "↓\(fmtMbps(store.netRx))  ↑\(fmtMbps(store.netTx)) Mbps")
            ForEach(store.netIfaces.prefix(2)) { f in
                row(f.name, "↓\(fmtMbps(f.rx_bps)) ↑\(fmtMbps(f.tx_bps))")
            }
        }
    }

    private func section<Content: View>(_ icon: String, _ tint: Color, _ title: String,
                                        _ value: String, _ hist: [Double],
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint).font(.system(size: 12)).frame(width: 16)
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Sparkline(values: hist, color: tint).frame(width: 52, height: 16)
                Text(value).font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint).frame(minWidth: 54, alignment: .trailing)
            }
            content().padding(.leading, 22)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 10))
    }
}

// Owns the combined status item and the detail popover. Shares the one store.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(
            rootView: MenuBarDetail().environmentObject(SnapshotStore.shared))
        return p
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SnapshotStore.shared
        store.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let host = NSHostingView(rootView: MenuBarReadout().environmentObject(store))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.action = #selector(togglePopover)
            button.target = self
        }
        item.isVisible = (UserDefaults.standard.object(forKey: "menuBarVisible") as? Bool) ?? true
        statusItem = item
    }

    // Toggled from the main window (App observes the @AppStorage flag).
    func setVisible(_ visible: Bool) { statusItem?.isVisible = visible }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
