import Foundation

/// The consistency grid, defined once (`docs/EXPORT_SCHEMA.md` §1).
///
/// Pure: the same rollup and the same targets always give the same four booleans.
public enum WinsCalculator {
    /// The four wins for `rollup`, judged against `goals`.
    ///
    /// Two rules are easy to get wrong and are spelled out in the contract:
    /// a rest day counts as a session win only when no workout landed, and a win against
    /// a `nil` measurement is `false` — never `true`, because `nil` means *not measured*.
    public static func wins(for rollup: DayRollup, goals: GoalSettingsDocument) -> Wins {
        Wins(session: isSessionWin(rollup.training),
             protein: isAtLeast(rollup.nutrition.proteinG, Double(goals.targets.proteinMinG)),
             steps: isAtLeast(rollup.activity.steps, goals.targets.steps),
             sleep: isAtLeast(rollup.sleep.asleepMinutes, goals.targets.sleepMinutes))
    }

    private static func isSessionWin(_ training: TrainingRollup) -> Bool {
        if training.sessionDone { return true }
        return training.sessionPlanned == .rest && training.workouts.isEmpty
    }

    private static func isAtLeast<Value: Comparable>(_ measured: Value?, _ target: Value) -> Bool {
        guard let measured else { return false }
        return measured >= target
    }
}

extension DayRollup {
    /// The same rollup with `wins` recomputed from its own measurements.
    public func withComputedWins(goals: GoalSettingsDocument) -> DayRollup {
        var copy = self
        copy.wins = WinsCalculator.wins(for: self, goals: goals)
        return copy
    }
}
