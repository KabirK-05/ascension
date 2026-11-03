import AscensionCore
import Foundation

/// How Today writes a number.
///
/// Centralised because `docs/DESIGN_RULES.md` §3.2 and §3.4 are about shape — the unit is
/// inline, the precision is real — and a format that lives in one place cannot drift card
/// by card. Every function here is pure and locale-independent in its structure.
enum TodayFormat {
    /// `462` → `"7h42"`. Minutes are always two digits, so the shape never changes.
    static func duration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        return "\(clamped / 60)h\(String(format: "%02d", clamped % 60))"
    }

    /// What VoiceOver says for a duration, which "7h42" does not read out usefully.
    static func spokenDuration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        return "\(clamped / 60) hours \(clamped % 60) minutes"
    }

    /// A whole number with the grouping separator the user's locale uses.
    static func count(_ value: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// An optional measurement, or the em dash that means *not measured*. Never `0`:
    /// zero steps and no step data are different facts.
    static func optionalCount(_ value: Int?) -> String {
        value.map(count) ?? unmeasured
    }

    static func optionalCount(_ value: Double?) -> String {
        value.map { count(Int($0.rounded())) } ?? unmeasured
    }

    /// The glyph a missing measurement gets. One character, no sentence (§1.4).
    static let unmeasured = "—"

    static let spokenUnmeasured = "Not measured"

    /// The local hour and minute a timestamp was taken at, read from the stamp's own
    /// offset so no timezone database is consulted and the result is reproducible.
    static func localMinuteOfDay(_ timestamp: Timestamp) -> Int? {
        let raw = timestamp.rawValue
        guard raw.count >= 16 else { return nil }
        let characters = Array(raw)
        guard let hours = twoDigits(characters, at: 11),
              let minutes = twoDigits(characters, at: 14),
              hours <= 23, minutes <= 59 else { return nil }
        return hours * 60 + minutes
    }

    private static func twoDigits(_ characters: [Character], at index: Int) -> Int? {
        guard characters.indices.contains(index + 1),
              let high = characters[index].wholeNumberValue,
              let low = characters[index + 1].wholeNumberValue,
              characters[index].isASCII, characters[index + 1].isASCII,
              (0...9).contains(high), (0...9).contains(low) else { return nil }
        return high * 10 + low
    }
}
