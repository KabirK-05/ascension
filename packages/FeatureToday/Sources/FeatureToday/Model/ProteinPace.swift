import AscensionCore
import Foundation

/// How far ahead or behind the protein target the day is, for the time of day.
///
/// A flat "148 of 150 g" says nothing at 09:00 and everything at 21:00, so the summary
/// line judges intake against the share of the eating day that has passed. Pure, and
/// driven by the injected clock, so a test can sit on any hour.
enum ProteinPace {
    /// The window intake is paced across. Nothing is expected before breakfast and the
    /// full target is expected by the end of the evening.
    static let startMinute = 8 * 60
    static let endMinute = 22 * 60

    /// Below this the gap is noise and the clause is not worth a line (§2.1).
    static let reportingThresholdGrams = 10.0

    /// `0...1` of the eating day that has passed at `minuteOfDay`.
    static func elapsedFraction(minuteOfDay: Int) -> Double {
        let span = Double(endMinute - startMinute)
        guard span > 0 else { return 1 }
        return min(max(Double(minuteOfDay - startMinute) / span, 0), 1)
    }

    /// Grams behind the pace, or `nil` when level or ahead.
    ///
    /// `nil` for an unmeasured clock as well: a gap that cannot be timed cannot be
    /// reported as one.
    static func gramsBehind(consumed: Double?, target: Int, at now: Timestamp) -> Double? {
        guard let minuteOfDay = TodayFormat.localMinuteOfDay(now) else { return nil }
        let expected = Double(target) * elapsedFraction(minuteOfDay: minuteOfDay)
        let deficit = expected - (consumed ?? 0)
        guard deficit >= reportingThresholdGrams else { return nil }
        return deficit
    }
}
