import AscensionCore
import Foundation

/// How the weight trend is computed.
public struct WeightTrendOptions: Hashable, Sendable {
    /// Days in the rolling average window.
    public var windowDays: Int

    /// Measurements a window needs before an average is emitted for it.
    ///
    /// A "7-day average" built from a single weigh-in is one weigh-in wearing a trend's
    /// clothes, and this is the number the calorie rule then acts on, so the bar is four.
    public var minimumSamples: Int

    /// Days back the rate of change compares against.
    public var rateSpanDays: Int

    /// The shortest gap the rate will accept, when no average sits exactly
    /// ``rateSpanDays`` back.
    public var minimumRateSpanDays: Int

    public init(windowDays: Int = 7, minimumSamples: Int = 4,
                rateSpanDays: Int = 7, minimumRateSpanDays: Int = 5) {
        self.windowDays = windowDays
        self.minimumSamples = minimumSamples
        self.rateSpanDays = rateSpanDays
        self.minimumRateSpanDays = minimumRateSpanDays
    }

    public static let standard = WeightTrendOptions()
}

/// Weight over time (spec §F6): daily points, the rolling average that actually matters,
/// the rate it is moving at, and how far is left.
public struct WeightTrend: Hashable, Sendable {
    /// Daily weigh-ins, earliest first. Only days that carry one.
    public let points: [DatedValue]

    /// The rolling average, one entry per day that has enough samples behind it.
    public let rollingAverage: [DatedValue]

    /// The latest rolling average — the number the user is shown and the calorie rule
    /// reads.
    public let latestAverageKg: Double?

    /// Change in the rolling average, in kg per week. Negative while losing.
    public let rateKgPerWeek: Double?

    /// Kilograms still to lose, from the rolling average. Negative once past the goal.
    public let kgToGoal: Double?

    public let goalWeightKg: Double
    public let asOf: CalendarDate
}

/// Weight trends (spec §F6). Pure functions over rollups.
public enum WeightTrendEngine {
    /// The full trend as of `asOf`.
    public static func trend(history: [DayRollup],
                             goals: GoalSettingsDocument,
                             asOf: CalendarDate,
                             options: WeightTrendOptions = .standard) -> WeightTrend {
        let points = measurements(history: history, asOf: asOf)
        let averages = rollingAverage(points: points, asOf: asOf, options: options)
        let latest = averages.latest(onOrBefore: asOf)?.value
        return WeightTrend(
            points: points,
            rollingAverage: averages,
            latestAverageKg: latest,
            rateKgPerWeek: rate(averages: averages, asOf: asOf, options: options),
            kgToGoal: latest.map { $0 - goals.body.goalWeightKg },
            goalWeightKg: goals.body.goalWeightKg,
            asOf: asOf)
    }

    /// Daily weigh-ins at or before `asOf`, earliest first.
    public static func measurements(history: [DayRollup], asOf: CalendarDate) -> [DatedValue] {
        history
            .filter { $0.date <= asOf }
            .compactMap { day in day.body.weightKg.map { DatedValue(date: day.date, value: $0) } }
            .chronological
    }

    /// The trailing mean for every day that has at least
    /// ``WeightTrendOptions/minimumSamples`` weigh-ins inside its window.
    ///
    /// Emitted per *measurement day*, not per calendar day: a day with no weigh-in adds
    /// no information, so it gets no point.
    public static func rollingAverage(points: [DatedValue],
                                      asOf: CalendarDate,
                                      options: WeightTrendOptions = .standard) -> [DatedValue] {
        guard options.windowDays > 0 else { return [] }
        let ordered = points.chronological
        return ordered.compactMap { point in
            let window = ordered.filter { candidate in
                let distance = candidate.date.days(until: point.date)
                return distance >= 0 && distance < options.windowDays
            }
            guard window.count >= options.minimumSamples else { return nil }
            let mean = window.reduce(0.0) { $0 + $1.value } / Double(window.count)
            return DatedValue(date: point.date, value: mean)
        }
    }

    /// Change in the rolling average, scaled to kg per week.
    ///
    /// Two averages are compared rather than a line fitted through daily weigh-ins:
    /// day-to-day weight is mostly water, and the average is the signal (spec §F6). The
    /// earlier average is the newest one at least ``WeightTrendOptions/minimumRateSpanDays``
    /// before the latest, so a missing day shortens the span instead of voiding the rate.
    public static func rate(averages: [DatedValue],
                            asOf: CalendarDate,
                            options: WeightTrendOptions = .standard) -> Double? {
        let ordered = averages.chronological
        guard let latest = ordered.last(where: { $0.date <= asOf }) else { return nil }
        let earlier = ordered.last { candidate in
            let gap = candidate.date.days(until: latest.date)
            return gap >= options.minimumRateSpanDays
        }
        guard let earlier else { return nil }
        let days = Double(earlier.date.days(until: latest.date))
        guard days > 0 else { return nil }
        return (latest.value - earlier.value) / days * 7
    }
}
