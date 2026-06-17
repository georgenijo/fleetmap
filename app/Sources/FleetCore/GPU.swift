import Foundation
import IOKit

// Per-process GPU accounting on Apple Silicon — read-only, no privileges.
//
// The kernel tags each AGXDeviceUserClient with its owning pid (IOUserClientCreator
// = "pid NNN, name") and a cumulative `accumulatedGPUTime` (nanoseconds). Summing
// per pid and diffing across samples gives each process's GPU busy-time delta — the
// same trick libproc gives us for CPU. The Collector divides that by the wall
// interval for an Activity-Monitor-style per-process GPU %. System-wide busy comes
// from `Device Utilization %` in IOAccelerator's PerformanceStatistics.
//
// Apple Silicon only: the AGX classes don't exist on Intel GPUs, so both calls
// return empty/0 there and the feature degrades to "no per-process GPU".
public enum GPU {

    // pid → cumulative GPU time (monotonic, arbitrary units). Empty on Intel.
    //
    // Each AGXDeviceUserClient carries its owning pid in IOUserClientCreator and a
    // cumulative GPU time per command-queue inside the AppUsage array (one entry
    // per queue) — NOT at the top level. Sum across queues, then across a pid's
    // clients.
    static func sampleByPID() -> [Int32: UInt64] {
        var out: [Int32: UInt64] = [:]
        forEachConforming("AGXDeviceUserClient") { props in
            guard let pid = pidFromCreator(props["IOUserClientCreator"]),
                  let usage = props["AppUsage"] as? [Any] else { return }
            var t: UInt64 = 0
            for case let u as [String: Any] in usage {
                if let g = u["accumulatedGPUTime"] as? NSNumber { t += g.uint64Value }
            }
            if t > 0 { out[pid, default: 0] += t }
        }
        return out
    }

    // System-wide GPU busy %, from IOAccelerator PerformanceStatistics. 0 if absent.
    static func deviceUtilization() -> Double { deviceStats().util }

    // System GPU utilization plus the renderer/tiler split, from the busiest GPU's
    // PerformanceStatistics dict. All 0 if unavailable (Intel/no accelerator).
    public static func deviceStats() -> (util: Double, renderer: Double, tiler: Double) {
        var u = 0.0, r = 0.0, t = 0.0
        forEachConforming("IOAccelerator") { props in
            guard let stats = props["PerformanceStatistics"] as? [String: Any] else { return }
            let util = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
                ?? (stats["GPU Activity(%)"] as? NSNumber)?.doubleValue
                ?? (stats["Device Utilization"] as? NSNumber)?.doubleValue ?? 0
            if util >= u {
                u = util
                r = (stats["Renderer Utilization %"] as? NSNumber)?.doubleValue ?? 0
                t = (stats["Tiler Utilization %"] as? NSNumber)?.doubleValue ?? 0
            }
        }
        return (u, r, t)
    }

    // ---- registry walk ----

    // The AGX user clients are !registered, so IOServiceGetMatchingServices misses
    // them. Walk the whole IOService plane and filter by class conformance — the
    // same thing `ioreg -c <class>` does.
    private static func forEachConforming(_ klass: String, _ body: ([String: Any]) -> Void) {
        var iter: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, "IOService",
                                       IOOptionBits(kIORegistryIterateRecursively),
                                       &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            guard IOObjectConformsTo(entry, klass) != 0 else { continue }
            var propsCF: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &propsCF, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsCF?.takeRetainedValue() as? [String: Any] else { continue }
            body(props)
        }
    }

    // "IOUserClientCreator" looks like "pid 555, WindowServer".
    private static func pidFromCreator(_ v: Any?) -> Int32? {
        guard let s = v as? String, let r = s.range(of: "pid ") else { return nil }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return Int32(digits)
    }
}
