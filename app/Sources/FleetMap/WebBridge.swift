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
    if let url = webResourceURL(resource) {
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    coordinator.web = web
    return web
}

// Locate a bundled web asset (`<resource>.html`) resiliently.
//
// SwiftPM's generated `Bundle.module` accessor is built for a bare CLI: it looks
// for `fleetmap_FleetMap.bundle` beside the executable (`Bundle.main.bundleURL`)
// and, failing that, at a *hard-coded build-machine path*. Neither survives
// repackaging into a `.app`: scripts/bundle.sh puts the resource bundle under
// `Contents/Resources/`, and the baked build path points at the CI runner. So in
// a downloaded build `Bundle.module` fatal-errors on first access. We therefore
// resolve via `Bundle.main` (which *is* `Contents/Resources`-aware) and only fall
// back to `Bundle.module` for `swift run`/tests, where it resolves cleanly and is
// never reached from inside the app.
private func webResourceURL(_ resource: String) -> URL? {
    // .app: the SwiftPM resource bundle sits in Contents/Resources/.
    if let nested = Bundle.main.url(forResource: "fleetmap_FleetMap", withExtension: "bundle"),
       let url = Bundle(url: nested)?.url(forResource: resource, withExtension: "html") {
        return url
    }
    // .app: web assets flattened directly into Contents/Resources/ (fallback layout).
    if let url = Bundle.main.url(forResource: resource, withExtension: "html") {
        return url
    }
    // swift run / swift test: SwiftPM's accessor finds the build-dir bundle.
    return Bundle.module.url(forResource: resource, withExtension: "html")
}
