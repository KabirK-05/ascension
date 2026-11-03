import AscensionCore
import Foundation

/// Everything the Trends tab and the Sunday review read, computed once (spec §F6, §F7).
public struct TrendsReport: Hashable, Sendable {
    public let asOf: CalendarDate
    public let weight: WeightTrend

    /// `nil` when the weekly rules do not fire. Never a mutation — see
    /// ``CalorieSuggestion``.
    public let calorieSuggestion: CalorieSuggestion?

    public let load: LoadTrend
    public let deload: DeloadStatus
    public let habits: HabitTrends
}

/// The trends engine (spec §F6). One pure function over synced days.
public enum TrendsEngine {
    public static func report(history: [DayRollup],
                              goals: GoalSettingsDocument,
                              program: ProgramDocument,
                              clock: EngineClock,
                              windowDays: Int = LoadThresholds.chronicWindowDays,
                              weightOptions: WeightTrendOptions = .standard) -> TrendsReport {
        let asOf = clock.today
        return TrendsReport(
            asOf: asOf,
            weight: WeightTrendEngine.trend(history: history, goals: goals, asOf: asOf,
                                            options: weightOptions),
            calorieSuggestion: CalorieAdjustEngine.suggestion(history: history, goals: goals,
                                                              asOf: asOf, options: weightOptions),
            load: LoadTrendEngine.trend(history: history, asOf: asOf),
            deload: DeloadDetector.status(program: program, goals: goals, asOf: asOf),
            habits: HabitTrendsEngine.trends(history: history, goals: goals, asOf: asOf,
                                             windowDays: windowDays))
    }
}
