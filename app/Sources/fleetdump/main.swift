import FleetCore
import Foundation

// Verify harness: take two samples (so CPU deltas exist), print the snapshot.
let c = Collector()
_ = c.collect()                 // prime CPU baseline
usleep(600_000)                 // 0.6s
let snap = c.collect()

FileHandle.standardError.write("seen=\(c.lastSeen) readable=\(c.lastSeen - c.lastSkipped) skipped(other-uid)=\(c.lastSkipped)\n".data(using: .utf8)!)

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try enc.encode(snap)
FileHandle.standardOutput.write(data)
print("")
