import SwiftUI
import WebKit
import FleetCore

// Which root UI the app presents. `classic` is the original native header +
// List/Graph tabs (unchanged). `orbital` is the full web shell — one WKWebView
// running the orbital.html star-system view + Pulse + Mission HUD.
enum UIShell: String, CaseIterable, Identifiable {
    case classic, orbital
    var id: String { rawValue }
    var title: String { self == .classic ? "Classic" : "Orbital" }
}

// The full-web orbital shell: the whole content area is one WKWebView hosting
// the self-contained, offline orbital.html. Fed with snapshots over the SAME
// window.__push bridge as the classic graph view.
struct OrbitalShellView: NSViewRepresentable {
    @EnvironmentObject var store: SnapshotStore

    func makeCoordinator() -> WebPushCoordinator { WebPushCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        makeWebShell(resource: "orbital", coordinator: context.coordinator)
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.push(store.snapshot)
    }
}
