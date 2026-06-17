import SwiftUI
import WebKit
import FleetCore

// The force-graph is the proven web canvas, embedded. Snapshots are pushed in
// over the WKWebView bridge (window.__push) — no HTTP server.
struct GraphView: NSViewRepresentable {
    @EnvironmentObject var store: SnapshotStore

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")   // let the vibrancy show through
        if let url = Bundle.module.url(forResource: "graph", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.web = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.push(store.snapshot)
    }

    final class Coordinator {
        weak var web: WKWebView?
        private var lastTS: Int64 = -1

        func push(_ snap: Snapshot) {
            guard snap.ts != lastTS, let web else { return }
            lastTS = snap.ts
            guard let data = try? JSONEncoder().encode(snap) else { return }
            let b64 = data.base64EncodedString()
            // decode UTF-8 bytes in-page (atob is latin1; the JSON has •→⚠ etc.)
            let js = """
            (function(){var b=atob('\(b64)');var u=Uint8Array.from(b,function(c){return c.charCodeAt(0)});\
            window.__push&&window.__push(new TextDecoder().decode(u));})()
            """
            web.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
