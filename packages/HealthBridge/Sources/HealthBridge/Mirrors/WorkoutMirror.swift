import AscensionCore
import Foundation

/// A workout Apple recorded, mirrored for trends and export (spec §6).
///
/// Keyed on the HealthKit UUID, which is what makes a mirror pass idempotent: re-reading
/// the same workout updates the row in place instead of adding a second one.
public struct WorkoutMirror: Hashable, Sendable, Identifiable {
    /// The HealthKit UUID, as a string, because that is what the contract carries.
    public var id: String
    public var activityType: String
    public var start: Date
    public var end: Date
    public var durationMinutes: Int
    public var activeEnergyKcal: Double?
    public var hrAvgBpm: Int?
    public var hrMaxBpm: Int?
    public var timeInZones: TimeInZonesMinutes
    /// Always "Apple Workout" for anything the Watch recorded (spec §6).
    public var source: String

    public init(id: String, activityType: String, start: Date, end: Date, durationMinutes: Int,
                activeEnergyKcal: Double? = nil, hrAvgBpm: Int? = nil, hrMaxBpm: Int? = nil,
                timeInZones: TimeInZonesMinutes = TimeInZonesMinutes(),
                source: String = WorkoutMirror.appleWorkoutSource) {
        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
        self.timeInZones = timeInZones
        self.source = source
    }

    public static let appleWorkoutSource = "Apple Workout"

    /// The contract shape this mirror feeds (`docs/EXPORT_SCHEMA.md` §1).
    public func summary(timeZone: TimeZone) -> WorkoutSummary {
        WorkoutSummary(
            healthKitId: id,
            type: activityType,
            startedAt: Timestamp(start, timeZone: timeZone),
            endedAt: Timestamp(end, timeZone: timeZone),
            durationMinutes: durationMinutes,
            activeEnergyKcal: activeEnergyKcal,
            hrAvgBpm: hrAvgBpm,
            hrMaxBpm: hrMaxBpm,
            timeInZonesMinutes: timeInZones,
            source: source)
    }
}

/// Builds workout mirrors from HealthKit records, and folds a new pass into the rows a
/// previous pass produced.
public enum WorkoutMirrorBuilder {
    /// One mirror per distinct workout, in a stable order.
    ///
    /// `heartRateSeries` is keyed on the workout UUID. A workout with no series gets no
    /// HR figures and empty zones — `nil`, never a zero that would read as a measurement.
    public static func mirrors(from records: [WorkoutRecord],
                               heartRateSeries: [UUID: [QuantityRecord]] = [:],
                               zones: HeartRateZones?) -> [WorkoutMirror] {
        MetricAggregator.deduplicatedWorkouts(records).map { record in
            mirror(for: record, series: heartRateSeries[record.id] ?? [], zones: zones)
        }
    }

    public static func mirror(for record: WorkoutRecord,
                              series: [QuantityRecord],
                              zones: HeartRateZones?) -> WorkoutMirror {
        let beats = MetricAggregator.deduplicated(series).filter { $0.metric == .heartRate }
        let average = MetricAggregator.average(beats).map { Int($0.rounded()) }
        let peak = MetricAggregator.maximum(beats).map { Int($0.rounded()) }
        let inZones = zones.map {
            TimeInZoneCalculator.minutes(series: beats, workout: record.interval, zones: $0)
        }
        return WorkoutMirror(
            id: record.id.uuidString,
            activityType: record.activityType,
            start: record.start,
            end: record.end,
            durationMinutes: record.durationMinutes,
            activeEnergyKcal: record.activeEnergyKcal,
            hrAvgBpm: average,
            hrMaxBpm: peak,
            timeInZones: inZones ?? TimeInZonesMinutes(),
            source: record.sourceName.isEmpty ? WorkoutMirror.appleWorkoutSource : record.sourceName)
    }

    /// Upsert on HealthKit UUID: incoming rows replace rows with the same id, deletions
    /// drop them, and the result is sorted the same way every time.
    ///
    /// This is the property the ticket turns on. `merge(merge(rows, rows), rows) == rows`
    /// for the same source data, no matter how often an observer fires.
    public static func merging(existing: [WorkoutMirror],
                               incoming: [WorkoutMirror],
                               deletedIds: Set<String> = []) -> [WorkoutMirror] {
        var byId: [String: WorkoutMirror] = [:]
        for mirror in existing { byId[mirror.id] = mirror }
        for mirror in incoming { byId[mirror.id] = mirror }
        for id in deletedIds { byId.removeValue(forKey: id) }
        return byId.values.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id < rhs.id
        }
    }
}
