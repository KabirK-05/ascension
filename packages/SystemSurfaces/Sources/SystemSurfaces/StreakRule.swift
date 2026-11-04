import AscensionCore
import AscensionEngines
import Foundation

/// How long the streak is.
///
/// `docs/SPEC.md` §F8 asks for a streak widget and does not say what a streak is, so the
/// rule is defined here, once, and tested — rather than in a view where nothing could
/// check it.
///
/// A day is **kept** when it scored at least ``threshold`` of the four daily wins
/// `docs/DESIGN_RULES.md` §6.2 already defines (session, protein, steps, sleep). Three of
/// four rather than four: a streak that a single late night ends is a streak nobody keeps,
/// and the grid above it already shows the full detail.
///
/// Today is counted only when it already qualifies, and skipped otherwise rather than
/// breaking the run — a streak must not collapse at 8 am because the day is young.
public enum StreakRule {
    /// Wins needed for a day to keep the streak.
    public static let threshold = 3

    public static func keeps(_ rollup: DayRollup) -> Bool {
        rollup.wins.total >= threshold
    }

    /// Consecutive kept days ending on `asOf`, counting backwards until one is missing or
    /// does not qualify.
    public static func length(history: [DayRollup], asOf: CalendarDate) -> Int {
        let byDate = Dictionary(history.map { ($0.date.rawValue, $0) },
                                uniquingKeysWith: { first, _ in first })

        var cursor = asOf
        var length = 0

        // Today in progress neither counts nor breaks the run.
        if let today = byDate[cursor.rawValue], keeps(today) {
            length += 1
        }
        cursor = cursor.adding(days: -1)

        while let day = byDate[cursor.rawValue], keeps(day) {
            length += 1
            cursor = cursor.adding(days: -1)
        }
        return length
    }
}
