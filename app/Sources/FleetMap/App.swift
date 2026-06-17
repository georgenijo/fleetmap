import SwiftUI
import AppKit

@main
struct FleetMapApp: App {
    @StateObject private var store = SnapshotStore()
    // Live, reactive UI-shell flag. Flipping it (View menu / env / default) swaps
    // the root instantly because ContentView reads the same @AppStorage key.
    @AppStorage("ui.shell") private var shell: UIShell = .orbital

    init() {
        FleetMapApp.resolveDefaultShell()
    }

    // Decide the *default* shell (the user can still override it from the View
    // menu, which persists over this). Precedence:
    //   1. FLEETMAP_UI=orbital|classic env var (hard override of the default)
    //   2. otherwise → default orbital (the classic native shell stays one
    //      click away in the View menu)
    // We use UserDefaults.register so a stored user choice always wins.
    static func resolveDefaultShell() {
        var fallback: UIShell = .orbital
        if let env = ProcessInfo.processInfo.environment["FLEETMAP_UI"],
           let forced = UIShell(rawValue: env.lowercased()) {
            fallback = forced
        }
        UserDefaults.standard.register(defaults: ["ui.shell": fallback.rawValue])
    }

    var body: some Scene {
        Window("fleetmap", id: "main") {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 640)
        .commands {
            // Live toggle between the classic native shell and the orbital web
            // shell. @AppStorage makes the switch reactive.
            CommandGroup(after: .toolbar) {
                Picker("Interface", selection: $shell) {
                    ForEach(UIShell.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
    }
}
