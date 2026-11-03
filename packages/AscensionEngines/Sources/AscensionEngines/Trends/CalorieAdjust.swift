import AscensionCore
import Foundation

/// What the rate of loss was over one week.
public struct WeeklyLoss: Hashable, Sendable {
    /// The day the week ends on.
    public let weekEnding: CalendarDate

    /// Kilograms lost per week — positive while losing, negative while gaining. `nil`
    /// when the rolling average had too little behind it to say.
    public let lossKgPerWeek: Double?

    public init(weekEnding: CalendarDate, lossKgPerWeek: Double?) {
        self.weekEnding = weekEnding
        self.lossKgPerWeek = lossKgPerWeek
    }
}

/// A proposed calorie target. **A suggestion and nothing else.**
///
/// The engine returns this value; it never writes a target and never emits a `Mutation`.
/// Accepting it is a `set_targets` write the user makes by tapping once, and the contract
/// carries the acceptance as `accept_suggestion { suggestionId }`
/// (`docs/EXPORT_SCHEMA.md` §3) — which is why ``id`` is derived from the inputs rather
/// than generated, so the same week always proposes the same identity.
public struct CalorieSuggestion: Hashable, Sendable {
    /// Stable for a given day and proposed value.
    public let id: String

    public let suggestedKcal: Int

    /// The target in force when the suggestion was made.
    public let currentKcal: Int

    /// A plain fact with units. Never advice.
    public let reason: String

    /// The weeks the rule read, most recent first.
    public let weeklyLoss: [WeeklyLoss]

    public let asOf: CalendarDate
}

/// The weekly calorie auto-adjust (spec §F6), suggest-only.
///
/// > avg loss < 0.3 kg/week for 2 weeks → suggest 2,000 kcal; > 0.8 kg/week → suggest
/// > 2,400 kcal. Never change targets silently.
///
/// Both comparisons are strict, so a week sitting exactly on 0.3 or 0.8 kg/week suggests
/// nothing.
public enum CalorieAdjustEngine {
    /// Loss slower than this, for ``consecutiveSlowWeeks`` weeks running, cuts calories.
    public static let slowLossKgPerWeek: Double = 0.3

    /// Loss faster than this raises them.
    public static let fastLossKgPerWeek: Double = 0.8

    public static let slowLossKcal = 2_000
    public static let fastLossKcal = 2_400

    /// The spec attaches a two-week persistence test to the slow branch only.
    public static let consecutiveSlowWeeks = 2

    /// Today's suggestion, or `nil` when the rules do not fire.
    ///
    /// Fast loss is checked first and acts on the latest week alone. The spec attaches no
    /// persistence test to it, and waiting a second week before suggesting *more* food
    /// would be the interpretation that keeps the deficit running — so this one reacts
    /// immediately.
    public static func suggestion(history: [DayRollup],
                                  goals: GoalSettingsDocument,
                                  asOf: CalendarDate,
                                  options: WeightTrendOptions = .standard) -> CalorieSuggestion? {
        let weeks = weeklyLoss(history: history, goals: goals, asOf: asOf,
                               count: consecutiveSlowWeeks, options: options)
        return suggestion(weeklyLoss: weeks, currentKcal: goals.targets.kcal, asOf: asOf)
    }

    /// The rule itself, over weekly rates that have already been derived.
    ///
    /// Split out from ``suggestion(history:goals:asOf:options:)`` so the thresholds can be
    /// tested exactly on 0.3 and 0.8 kg/week rather than approached through a synthetic
    /// run of weigh-ins. `weeklyLoss` is most recent first.
    public static func suggestion(weeklyLoss weeks: [WeeklyLoss],
                                  currentKcal current: Int,
                                  asOf: CalendarDate) -> CalorieSuggestion? {
        if let latest = weeks.first?.lossKgPerWeek, latest > fastLossKgPerWeek {
            let reason = "losing \(Phrase.decimal(latest, places: 2)) kg/week"
            return make(kcal: fastLossKcal, current: current, reason: reason,
                        weeks: weeks, asOf: asOf)
        }

        let slow = weeks.prefix(consecutiveSlowWeeks).compactMap(\.lossKgPerWeek)
        if slow.count == consecutiveSlowWeeks, slow.allSatisfy({ $0 < slowLossKgPerWeek }) {
            let rates = slow.map { Phrase.decimal($0, places: 2) }.joined(separator: " and ")
            let reason = "losing \(rates) kg/week over \(consecutiveSlowWeeks) weeks"
            return make(kcal: slowLossKcal, current: current, reason: reason,
                        weeks: weeks, asOf: asOf)
        }
        return nil
    }

    /// The last `count` weekly rates, most recent first.
    public static func weeklyLoss(history: [DayRollup],
                                  goals: GoalSettingsDocument,
                                  asOf: CalendarDate,
                                  count: Int,
                                  options: WeightTrendOptions = .standard) -> [WeeklyLoss] {
        guard count > 0 else { return [] }
        let points = WeightTrendEngine.measurements(history: history, asOf: asOf)
        let averages = WeightTrendEngine.rollingAverage(points: points, asOf: asOf,
                                                        options: options)
        return (0..<count).map { index in
            let weekEnding = asOf.adding(days: -index * 7)
            let rate = WeightTrendEngine.rate(averages: averages, asOf: weekEnding,
                                              options: options)
            return WeeklyLoss(weekEnding: weekEnding, lossKgPerWeek: rate.map { -$0 })
        }
    }

    /// A suggestion, unless it would propose the target already in force or a value the
    /// contract would reject (`docs/EXPORT_SCHEMA.md` §2.1).
    private static func make(kcal: Int, current: Int, reason: String,
                             weeks: [WeeklyLoss], asOf: CalendarDate) -> CalorieSuggestion? {
        guard kcal != current, GoalSettingsDocument.kcalRange.contains(kcal) else { return nil }
        return CalorieSuggestion(id: "calorie-\(asOf.rawValue)-\(kcal)",
                                 suggestedKcal: kcal,
                                 currentKcal: current,
                                 reason: reason,
                                 weeklyLoss: weeks,
                                 asOf: asOf)
    }
}
