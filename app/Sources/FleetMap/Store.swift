import SwiftUI
import FleetCore

@MainActor
final class SnapshotStore: ObservableObject {
    static let shared = SnapshotStore()

    @Published var snapshot = Snapshot(ts: 0, nodes: [], edges: [], note: nil)
    @Published var skipped = 0

    // rolling history for the menu-bar sparklines (~60s at 1.5s cadence)
    @Published var socHist: [Double] = []
    @Published var gpuHist: [Double] = []
    @Published var lanHist: [Double] = []   // combined Mbps
    private let histCap = 40

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
                pushHistory()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func pushHistory() {
        func push(_ a: inout [Double], _ v: Double) {
            a.append(v)
            if a.count > histCap { a.removeFirst(a.count - histCap) }
        }
        push(&socHist, snapshot.soc_temp)
        push(&gpuHist, snapshot.gpu_util)
        push(&lanHist, (snapshot.net_rx_bps + snapshot.net_tx_bps) * 8 / 1_000_000)
    }

    var totalCPU: Double { snapshot.nodes.reduce(0) { $0 + $1.cpu } }
    var totalGPU: Double { snapshot.gpu_util }
    var totalRAMGB: Double { snapshot.nodes.reduce(0) { $0 + $1.rss_mb } / 1024 }
    var socTemp: Double { snapshot.soc_temp }
    var netRx: Double { snapshot.net_rx_bps }
    var netTx: Double { snapshot.net_tx_bps }
    var netIfaces: [NetIface] { snapshot.net_ifaces }
}
