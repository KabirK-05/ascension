import AscensionCore
import Foundation

/// The habit numbers on the Trends tab (spec §F6).
public struct HabitTrends: Hashable, Sendable {
    /// Days the window spans, including `asOf`.
    public let windowDays: Int

    /// Percentage of days in the window that hit the protein floor.
    ///
    /// The denominator is every day in the window, not only the days that were logged —
    /// the same rule the contract gives the consistency grid, where "a win against a
    /// `null` measurement is `false`, never `true`" (`docs/EXPORT_SCHEMA.md` §1). A day
    /// nobody logged did not hit 140 g.
    public let proteinHitRatePct: Double

    public let proteinHitDays: Int

    /// Sessions completed as a percentage of training days the program planned. `nil`
    /// when the window planned none, which is not the same as 0%.
    public let adherencePct: Double?

    public let plannedSessions: Int
    public let completedSessions: Int

    public let vo2MaxSeries: [DatedValue]
    public let restingHrSeries: [DatedValue]
    public let sleepMinutesSeries: [DatedValue]
    public let sleepConsistencySeries: [DatedValue]

    public let asOf: CalendarDate
}

/// Protein hit-rate, adherence and the vitals/sleep series (spec §F6).
public enum HabitTrendsEngine {
    public static func trends(history: [DayRollup],
                              goals: GoalSettingsDocument,
                              asOf: CalendarDate,
                              windowDays: Int = LoadThresholds.chronicWindowDays) -> HabitTrends {
        let span = max(1, windowDays)
        let dates = Set(asOf.trailingWindow(days: span).map(\.rawValue))
        let days = history.filter { dates.contains($0.date.rawValue) }.sorted { $0.date < $1.date }

        let floor = Double(goals.targets.proteinMinG)
        let hits = days.count { day in
            guard let protein = day.nutrition.proteinG else { return false }
            return protein >= floor
        }
        let planned = days.count { $0.training.sessionPlanned?.isTrainingDay == true }
        let completed = days.count { $0.training.sessionPlanned?.isTrainingDay == true
            && $0.training.sessionDone }

        return HabitTrends(
            windowDays: span,
            proteinHitRatePct: Double(hits) / Double(span) * 100,
            proteinHitDays: hits,
            adherencePct: planned > 0 ? Double(completed) / Double(planned) * 100 : nil,
            plannedSessions: planned,
            completedSessions: completed,
            vo2MaxSeries: series(days) { $0.vitals.vo2Max },
            restingHrSeries: series(days) { $0.vitals.restingHrBpm.map(Double.init) },
            sleepMinutesSeries: series(days) { $0.sleep.asleepMinutes.map(Double.init) },
            sleepConsistencySeries: series(days) { $0.sleep.consistencySd7Minutes },
            asOf: asOf)
    }

    /// One series, holding only the days that carry the measurement.
    private static func series(_ days: [DayRollup],
                               _ value: (DayRollup) -> Double?) -> [DatedValue] {
        days.compactMap { day in value(day).map { DatedValue(date: day.date, value: $0) } }
    }
}
