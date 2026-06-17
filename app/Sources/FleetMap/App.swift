import SwiftUI
import AppKit

@main
struct FleetMapApp: App {
    @StateObject private var store = SnapshotStore()

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

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
    }
}
