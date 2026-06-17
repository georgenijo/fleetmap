import WebKit
import FleetCore

// Shared WKWebView snapshot-push plumbing. Both the classic graph view and the
// orbital shell feed their bundled HTML over the same one-way bridge:
//   window.__push(jsonString)   // jsonString = the encoded Snapshot
// Keeping a single implementation avoids the two views drifting into subtly
// different encoders / escaping.
final class WebPushCoordinator {
    weak var web: WKWebView?
    private var lastTS: Int64 = -1

    @MainActor func push(_ snap: Snapshot) {
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

// Loads a bundled offline HTML resource into a vibrancy-friendly WKWebView and
// keeps it fed with snapshots. Reused by GraphView (graph.html) and
// OrbitalShellView (orbital.html).
@MainActor
func makeWebShell(resource: String, coordinator: WebPushCoordinator) -> WKWebView {
    let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    web.setValue(false, forKey: "drawsBackground")   // let the vibrancy show through
    if let url = Bundle.module.url(forResource: resource, withExtension: "html") {
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    coordinator.web = web
    return web
}
