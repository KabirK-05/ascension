import AscensionCore
import AscensionEngines
import Foundation

/// The numbers the Sunday review is made of (spec §F7).
///
/// Every field is read straight off ``TrendsReport``. This type exists so the card and
/// the text generator read the *same* numbers, and so the facts handed to an on-device
/// model are a closed, checked set rather than a prompt assembled from a store.
///
/// Spec §F7 asks for *average protein*. The engine does not publish one — `HabitTrends`
/// reports the hit-rate against the protein floor and no mean — so this carries the
/// hit-rate instead. Computing a mean from raw rollups here would put nutrition
/// arithmetic in the view layer, which the engines own (spec §8). The hit-rate is also
/// the number the program actually turns on: the floor is the rule, not the average.
public struct WeeklyReviewFacts: Hashable, Sendable {
    public let weekEnding: CalendarDate

    public let sessionsCompleted: Int
    public let sessionsPlanned: Int

    /// Percentage of days in the window that hit the protein floor, and the floor itself.
    public let proteinHitRatePct: Double
    public let proteinFloorG: Int

    /// The rolling average, and the rate it is moving at in kg/week.
    public let weightAverageKg: Double?
    public let weightRateKgPerWeek: Double?
    public let kgToGoal: Double?
    public let goalWeightKg: Double

    /// Mean nightly sleep over the window, in minutes. `nil` when nothing was measured.
    ///
    /// The arithmetic mean of the engine's own ``HabitTrends/sleepMinutesSeries``: an
    /// aggregate of a published series, with no threshold in it and no second
    /// implementation anywhere to drift from.
    public let sleepMeanMinutes: Double?

    /// The nightly sleep target in force. Read from the user's goals, never derived.
    public let sleepTargetMinutes: Int

    public let suggestion: CalorieSuggestion?
    public let deload: DeloadStatus
    public let acuteChronicRatio: Double?
    public let band: AcwrBand?

    public init(report: TrendsReport, goals: GoalSettingsDocument) {
        weekEnding = report.asOf
        sessionsCompleted = report.habits.completedSessions
        sessionsPlanned = report.habits.plannedSessions
        proteinHitRatePct = report.habits.proteinHitRatePct
        proteinFloorG = goals.targets.proteinMinG
        weightAverageKg = report.weight.latestAverageKg
        weightRateKgPerWeek = report.weight.rateKgPerWeek
        kgToGoal = report.weight.kgToGoal
        goalWeightKg = report.weight.goalWeightKg
        sleepMeanMinutes = Self.mean(report.habits.sleepMinutesSeries)
        sleepTargetMinutes = goals.targets.sleepMinutes
        suggestion = report.calorieSuggestion
        deload = report.deload
        acuteChronicRatio = report.load.acuteChronicRatio
        band = report.load.band
    }

    private static func mean(_ series: [DatedValue]) -> Double? {
        guard !series.isEmpty else { return nil }
        return series.reduce(0.0) { $0 + $1.value } / Double(series.count)
    }
}
