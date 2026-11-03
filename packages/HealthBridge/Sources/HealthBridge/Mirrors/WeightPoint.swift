import AscensionCore
import Foundation

/// One day's weight (spec §6).
///
/// The 7-day average and the rate of change the trends screen shows are F6's work, not
/// this module's: HealthBridge mirrors what the scale said and stops there.
public struct WeightPoint: Hashable, Sendable, Identifiable {
    public var id: CalendarDate { date }
    public var date: CalendarDate
    public var weightKg: Double
    public var measuredAt: Date
    /// The HealthKit UUID this point came from.
    public var sourceSampleId: String

    public init(date: CalendarDate, weightKg: Double, measuredAt: Date, sourceSampleId: String) {
        self.date = date
        self.weightKg = weightKg
        self.measuredAt = measuredAt
        self.sourceSampleId = sourceSampleId
    }
}

/// Turns body-mass samples into one point per day.
public enum WeightPointBuilder {
    /// The last reading of each day wins.
    ///
    /// Matching the read layer's `mostRecent`, and matching how corrections behave: a
    /// user who re-weighs after noticing a bad reading expects the later number. Ties
    /// break on UUID so the row is identical on every pass.
    public static func points(from records: [QuantityRecord], timeZone: TimeZone) -> [WeightPoint] {
        var byDate: [CalendarDate: [QuantityRecord]] = [:]
        for record in MetricAggregator.deduplicated(records) where record.metric == .bodyMass {
            guard let date = DayWindow.calendarDate(for: record.end, timeZone: timeZone) else { continue }
            byDate[date, default: []].append(record)
        }
        return byDate.compactMap { date, records -> WeightPoint? in
            guard let winner = MetricAggregator.latest(records) else { return nil }
            return WeightPoint(date: date, weightKg: winner.value, measuredAt: winner.end,
                               sourceSampleId: winner.id.uuidString)
        }
        .sorted { $0.date < $1.date }
    }

    /// Upsert on date, so re-running a pass over the same samples changes nothing.
    public static func merging(existing: [WeightPoint], incoming: [WeightPoint]) -> [WeightPoint] {
        var byDate: [CalendarDate: WeightPoint] = [:]
        for point in existing { byDate[point.date] = point }
        for point in incoming { byDate[point.date] = point }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
