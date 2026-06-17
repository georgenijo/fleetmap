import SwiftUI
import AppKit

@main
struct FleetMapApp: App {
    // The status item (live SoC/GPU/LAN readout) is owned by MenuBarController;
    // the window scene and the controller share SnapshotStore.shared.
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBar
    @StateObject private var store = SnapshotStore.shared
    @AppStorage("menuBarVisible") private var menuBarVisible = true

    var body: some Scene {
        Window("fleetmap", id: "main") {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onChange(of: menuBarVisible) { _, visible in menuBar.setVisible(visible) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 640)
    }
}
