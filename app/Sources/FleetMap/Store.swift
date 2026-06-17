import SwiftUI
import FleetCore

@MainActor
final class SnapshotStore: ObservableObject {
    @Published var snapshot = Snapshot(ts: 0, nodes: [], edges: [], note: nil)
    @Published var skipped = 0

    private let collector = Collector()
    private var task: Task<Void, Never>?
    let interval: Duration = .milliseconds(1500)

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor in
            _ = collector.collect()                       // prime CPU baseline
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                snapshot = collector.collect()
                skipped = collector.lastSkipped
                try? await Task.sleep(for: interval)
            }
        }
    }

    var totalCPU: Double { snapshot.nodes.reduce(0) { $0 + $1.cpu } }
    var totalRAMGB: Double { snapshot.nodes.reduce(0) { $0 + $1.rss_mb } / 1024 }
}
