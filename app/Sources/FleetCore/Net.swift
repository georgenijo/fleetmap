import Darwin

// System-wide network throughput from interface byte counters (getifaddrs /
// if_data). Cumulative; the Collector diffs over the wall interval for bytes/sec.
// Sums all non-loopback interfaces (en/wifi/utun/bridge…). Counters are 32-bit
// and can wrap on very busy long-lived links; a wrap shows as one dropped sample
// (delta clamped to 0), which is fine for a menu-bar readout.
enum NetThroughput {
    // cumulative (rx, tx) bytes per non-loopback interface
    static func perInterface() -> [(name: String, rx: UInt64, tx: UInt64)] {
        var out: [(String, UInt64, UInt64)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var ptr = head
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, Int32(addr.pointee.sa_family) == AF_LINK,
               let raw = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo") {
                    let d = raw.assumingMemoryBound(to: if_data.self).pointee
                    out.append((name, UInt64(d.ifi_ibytes), UInt64(d.ifi_obytes)))
                }
            }
            ptr = ifa.ifa_next
        }
        return out
    }
}
