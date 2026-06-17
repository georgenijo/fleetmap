import SwiftUI
import WebKit
import FleetCore

// The force-graph is the proven web canvas, embedded. Snapshots are pushed in
// over the WKWebView bridge (window.__push) — no HTTP server. The push plumbing
// lives in WebBridge.swift and is shared with the orbital shell.
struct GraphView: NSViewRepresentable {
    @EnvironmentObject var store: SnapshotStore

    func makeCoordinator() -> WebPushCoordinator { WebPushCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        makeWebShell(resource: "graph", coordinator: context.coordinator)
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.push(store.snapshot)
    }
}
