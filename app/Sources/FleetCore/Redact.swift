import Foundation

// Mask credential-shaped substrings in a command line before it's shown.
// Ported from the Go tool so both stay in sync.

private let kvSecret = try! NSRegularExpression(
    pattern: #"(?i)\b(token|secret|password|passwd|pwd|api[_-]?key|apikey|access[_-]?key|client[_-]?secret|auth|bearer|key)([=: ]+)(\S+)"#)
private let tokenLike = try! NSRegularExpression(
    pattern: #"\b(sk-[A-Za-z0-9_-]{12,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{12,}|ASIA[0-9A-Z]{12,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,})"#)
private let longOpaque = try! NSRegularExpression(
    pattern: #"\b[A-Fa-f0-9]{32,}\b|\b[A-Za-z0-9+/]{40,}={0,2}\b"#)

private let mask = "•••"

public func redact(_ cmd: String) -> String {
    if cmd.isEmpty { return cmd }
    var s = cmd as NSString
    // key=value: keep key+sep, mask the value
    s = kvSecret.stringByReplacingMatches(
        in: s as String, range: NSRange(location: 0, length: s.length),
        withTemplate: "$1$2\(mask)") as NSString
    s = tokenLike.stringByReplacingMatches(
        in: s as String, range: NSRange(location: 0, length: s.length),
        withTemplate: mask) as NSString
    // longOpaque: only mask if it isn't a path-ish token
    let str = s as String
    let matches = longOpaque.matches(in: str, range: NSRange(location: 0, length: (str as NSString).length))
    var result = str
    for m in matches.reversed() {
        guard let r = Range(m.range, in: result) else { continue }
        let hit = String(result[r])
        if hit.contains("/") || hit.contains("\\") || hit.contains(".") { continue }
        result.replaceSubrange(r, with: mask)
    }
    return result
}
