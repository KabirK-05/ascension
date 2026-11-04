import Foundation

// How a reason is worded.
//
// Readiness reasons are plain facts with units — "slept 6h10", "HRV −18% vs baseline" —
// and never advice or encouragement (spec §F5, `docs/DESIGN_RULES.md` §1). Keeping the
// wording in one place is what stops a motivational sentence from drifting into one
// branch of the engine later.

enum Phrase {
    /// The typographic minus the spec's own examples use.
    static let minus = "\u{2212}"

    /// `462` → `"7h42"`. Minutes are always two digits so the shape never changes.
    static func duration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        return "\(clamped / 60)h\(String(format: "%02d", clamped % 60))"
    }

    /// `-0.18` → `"−18%"`, `0.06` → `"+6%"`, `0` → `"0%"`.
    static func signedPercent(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        if percent > 0 { return "+\(percent)%" }
        if percent < 0 { return "\(minus)\(abs(percent))%" }
        return "0%"
    }

    /// `-3` → `"−3"`, `5` → `"+5"`, `0` → `"0"`.
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\(minus)\(abs(value))" }
        return "0"
    }

    /// A number with at most `places` decimals and no trailing zeroes: `1.60` → `"1.6"`.
    static func decimal(_ value: Double, places: Int = 1) -> String {
        let text = String(format: "%.\(max(0, places))f", value)
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// `"quads"`, `"back and quads"`, `"back, quads and hamstrings"`.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }
}
