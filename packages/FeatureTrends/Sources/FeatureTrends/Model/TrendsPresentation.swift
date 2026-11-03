import AscensionCore
import AscensionEngines
import Foundation

/// One point on a chart, dated with a real `Date` so Swift Charts can scale an axis.
public struct ChartPoint: Hashable, Sendable, Identifiable {
    public let date: Date
    public let value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Weight (spec §F6). The rolling average is the hero; the daily points are context.
public struct WeightPanel: Hashable, Sendable {
    /// Daily weigh-ins.
    public let points: [ChartPoint]

    /// The 7-day average — the line drawn prominently, because it is the number that
    /// matters.
    public let average: [ChartPoint]

    public let latestAverage: String
    public let spokenLatestAverage: String
    public let rate: String
    public let spokenRate: String
    public let toGoal: String
    public let spokenToGoal: String

    /// What VoiceOver reads instead of the chart itself (§4.3).
    public let chartDescription: String
}

/// The calorie auto-adjust, surfaced for one tap (spec §F6).
public struct SuggestionPanel: Hashable, Sendable {
    /// The `suggestionId` an `accept_suggestion` mutation carries.
    public let id: String
    public let suggestedKcal: Int
    public let currentKcal: Int

    /// The engine's own wording. A fact with units, never advice.
    public let reason: String
}

/// Load management and the deload prompt (spec §F6).
public struct LoadPanel: Hashable, Sendable {
    public let weekly: [ChartPoint]
    public let ratio: String
    public let spokenRatio: String
    public let band: AcwrBand?
    public let bandName: String

    /// Set only when the engine warns (§F6: "spike warning after layoffs").
    public let spikeAfterLayoff: Bool
    public let layoffDays: Int

    /// Set only when the cadence week has arrived.
    public let deloadWeek: Int?

    /// Days in the window whose load could not be computed.
    public let unmeasuredDays: Int

    public let chartDescription: String
}

/// Protein hit-rate and adherence (spec §F2, §F6).
public struct HabitsPanel: Hashable, Sendable {
    public let proteinHitRate: String
    public let proteinHitDays: Int
    public let windowDays: Int
    public let adherence: String
    public let completedSessions: Int
    public let plannedSessions: Int
}

/// One vitals or sleep series, with the numbers that frame it.
public struct SeriesPanel: Hashable, Sendable, Identifiable {
    public let label: String
    public let latest: String
    public let unit: String?
    public let spokenLatest: String
    public let points: [ChartPoint]
    public let chartDescription: String

    public var id: String { label }
}

/// The Sunday card (spec §F7).
public struct ReviewPanel: Hashable, Sendable {
    public let facts: WeeklyReviewFacts
    public let rows: [ReviewRow]
    public let text: WeeklyReviewText?
}

/// One measured fact in the review.
public struct ReviewRow: Hashable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let unit: String?
    public let spokenValue: String

    public var id: String { label }
}

/// Everything the Trends tab draws, already turned into strings and points.
public struct TrendsPresentation: Hashable, Sendable {
    public let weight: WeightPanel
    public let suggestion: SuggestionPanel?
    public let load: LoadPanel
    public let habits: HabitsPanel
    public let series: [SeriesPanel]
    public let review: ReviewPanel?
}
