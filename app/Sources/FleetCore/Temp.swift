import Foundation
import CIOHID

// Apple Silicon die temperatures via the private IOHIDEventSystemClient API
// (CIOHID shim). No sudo, no entitlement; returns empty on Intel / if unavailable.
public enum Temp {
    private static let stride = 64
    private static let cap = 64

    // All temperature sensors as (name, °C).
    public static func readAll() -> [(name: String, c: Double)] {
        var names = [CChar](repeating: 0, count: stride * cap)
        var values = [Double](repeating: 0, count: cap)
        let n = Int(fleet_read_temps(&names, Int32(stride), &values, Int32(cap)))
        guard n > 0 else { return [] }
        var out: [(String, Double)] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let name = names.withUnsafeBufferPointer { buf -> String in
                String(cString: buf.baseAddress! + i * stride)
            }
            out.append((name, values[i]))
        }
        return out
    }

    // SoC die temperature — a single "how hot is the silicon" number. On Apple
    // Silicon the die sensors are named "...tdie..." (vs "tcal" calibration,
    // "tdev" peripheral, "NAND ...", etc.). A chip can carry multiple sensor
    // banks at very different temps (an active compute die ~95° next to an idle
    // bank ~60°); a flat average across both is misleading. So average only the
    // die sensors within `band`°C of the hottest — i.e. the active die cluster.
    public static func averageSoC(band: Double = 15) -> Double {
        let dies = readAll().filter { s in
            guard s.c > 0, s.c < 130 else { return false }
            let n = s.name.lowercased()
            return n.contains("tdie") && !n.contains("tcal")
        }
        guard let hottest = dies.map(\.c).max() else { return 0 }
        let active = dies.filter { $0.c >= hottest - band }
        return active.reduce(0) { $0 + $1.c } / Double(active.count)
    }
}
