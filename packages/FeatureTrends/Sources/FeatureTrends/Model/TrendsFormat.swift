import Foundation

/// How Trends writes a number.
///
/// One place, because `docs/DESIGN_RULES.md` §3.2 and §3.4 are about shape — the unit is
/// inline, the precision is real — and a format that lives in one place cannot drift card
/// by card. Every function here is pure.
enum TrendsFormat {

    /// The glyph a missing measurement gets. One character, never a sentence (§1.4).
    static let unmeasured = "—"

    static let spokenUnmeasured = "Not measured"

    /// The typographic minus, matching the engines' own wording.
    static let minus = "\u{2212}"

    /// A number with at most `places` decimals and no trailing zeroes: `73.60` → `"73.6"`.
    ///
    /// A value that rounds to zero prints as `0`, never `−0`: the sign would claim a
    /// direction the rounded number no longer carries.
    static func decimal(_ value: Double, places: Int = 1) -> String {
        let scale = pow(10, Double(max(0, places)))
        let rounded = (value * scale).rounded() / scale
        let text = String(format: "%.\(max(0, places))f", rounded == 0 ? 0 : rounded)
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// A signed decimal using the typographic minus: `-0.42` → `"−0.42"`, `0.42` → `"+0.42"`.
    ///
    /// Zero carries no sign. A rate that rounds to zero is neither a gain nor a loss, and
    /// printing `+0` would claim a direction the data does not have.
    static func signedDecimal(_ value: Double, places: Int = 2) -> String {
        let rounded = (value * pow(10, Double(places))).rounded() / pow(10, Double(places))
        if rounded > 0 { return "+\(decimal(rounded, places: places))" }
        if rounded < 0 { return "\(minus)\(decimal(abs(rounded), places: places))" }
        return decimal(0, places: places)
    }

    /// What VoiceOver says for a signed decimal, which `"−0.42"` does not read usefully.
    static func spokenSignedDecimal(_ value: Double, places: Int = 2, unit: String) -> String {
        let rounded = (value * pow(10, Double(places))).rounded() / pow(10, Double(places))
        let magnitude = decimal(abs(rounded), places: places)
        if rounded > 0 { return "Up \(magnitude) \(unit)" }
        if rounded < 0 { return "Down \(magnitude) \(unit)" }
        return "No change"
    }

    /// `462` → `"7h42"`. Minutes are always two digits, so the shape never changes (§3.2).
    static func duration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        return "\(clamped / 60)h\(String(format: "%02d", clamped % 60))"
    }

    static func spokenDuration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        return "\(clamped / 60) hours \(clamped % 60) minutes"
    }

    /// A percentage as an integer. §3.4: never a precision the data does not have.
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// A whole number in the user's locale grouping.
    static func count(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.precision(.fractionLength(0)))
    }

    /// An optional measurement, or the em dash. Never `0`: zero and absent are different
    /// facts, and the contract says so (`docs/EXPORT_SCHEMA.md` §1).
    static func optional(_ value: Double?, places: Int = 1) -> String {
        value.map { decimal($0, places: places) } ?? unmeasured
    }
}
