import AscensionCore
import DesignSystem
import Foundation

/// `DayRollup` as the consistency grid reads it.
///
/// `DesignSystem` was built against its own `DayWins` so the component could ship
/// without importing the contract. This is the join, and it is deliberately the *same*
/// function as ``WinsCalculator``: the thresholds come from the user's own targets
/// rather than the component's defaults, and `FeatureTodayTests` asserts that the
/// intensity drawn in a cell always equals `WinsCalculator`'s `wins.total` for the same
/// rollup. The grid cannot disagree with the contract because the two are proved equal,
/// not because one trusts the other.
enum ConsistencyMapping {

    /// The user's own targets, in the shape the grid scores against.
    static func thresholds(for targets: GoalTargets) -> ConsistencyThresholds {
        ConsistencyThresholds(proteinGrams: targets.proteinMinG,
                              steps: targets.steps,
                              sleepHours: Double(targets.sleepMinutes) / 60)
    }

    /// `WinsCalculator.isSessionWin`, in the component's vocabulary: a session trained
    /// and a planned rest day honoured are both wins; anything else is missed.
    static func outcome(of training: TrainingRollup) -> SessionOutcome {
        if training.sessionDone { return .asPlanned }
        if training.sessionPlanned == .rest, training.workouts.isEmpty { return .rest }
        return .missed
    }

    /// A day's four measurements. A `nil` measurement maps to a value that cannot clear
    /// its threshold, which is what *not measured* means for a win (`EXPORT_SCHEMA` §1).
    ///
    /// Protein floors rather than rounds, so a day on 139.6 g against a 140 g floor stays
    /// a loss exactly as `WinsCalculator` scores it.
    static func wins(of rollup: DayRollup) -> DayWins {
        DayWins(session: outcome(of: rollup.training),
                proteinGrams: Int((rollup.nutrition.proteinG ?? 0).rounded(.down)),
                steps: rollup.activity.steps ?? 0,
                sleepHours: Double(rollup.sleep.asleepMinutes ?? 0) / 60)
    }

    /// Whether the day carries anything at all. A day with no measurement and no
    /// training draws as an empty cell and is not tappable, rather than as a confident
    /// zero (§6.5).
    static func hasData(_ rollup: DayRollup) -> Bool {
        rollup.nutrition.proteinG != nil
            || rollup.activity.steps != nil
            || rollup.sleep.asleepMinutes != nil
            || rollup.training.sessionDone
            || !rollup.training.workouts.isEmpty
            || rollup.training.sessionPlanned != nil
    }

    /// The grid's days, in the calendar the screen is drawn in.
    static func days(from history: [DayRollup], calendar: Calendar) -> [ConsistencyDay] {
        history.compactMap { rollup in
            guard let date = date(of: rollup.date, in: calendar) else { return nil }
            return ConsistencyDay(date: date, wins: hasData(rollup) ? wins(of: rollup) : nil)
        }
    }

    /// Noon on a calendar date, so a daylight-saving shift cannot move the day.
    static func date(of day: CalendarDate, in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: day.year, month: day.month,
                                           day: day.day, hour: 12))
    }

    /// The calendar the grid is laid out in: the user's own week start, in the
    /// snapshot's timezone rather than the device's.
    static func calendar(timezone identifier: String) -> Calendar {
        var calendar = Calendar.current
        if let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }
        return calendar
    }
}
