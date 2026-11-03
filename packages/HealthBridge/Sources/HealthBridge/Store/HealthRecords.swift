import Foundation

/// One quantity sample, already converted to the metric's canonical unit.
///
/// `id` is the HealthKit UUID. Every mirror in this module is keyed on it, which is what
/// makes a second pass over the same data produce the same rows instead of duplicates.
public struct QuantityRecord: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var metric: HealthMetric
    public var value: Double
    public var start: Date
    public var end: Date
    public var sourceName: String

    public init(id: UUID, metric: HealthMetric, value: Double, start: Date, end: Date,
                sourceName: String) {
        self.id = id
        self.metric = metric
        self.value = value
        self.start = start
        self.end = end
        self.sourceName = sourceName
    }

    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// What a sleep-analysis sample claims about a stretch of time.
///
/// HealthKit's stages collapse to two things this app cares about: you were asleep, or
/// you were in bed. `awake` is kept so an in-bed interval can have its awake stretches
/// removed rather than counted as sleep.
public enum SleepStage: String, Codable, Hashable, Sendable, CaseIterable {
    case inBed
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        case .inBed, .awake: return false
        }
    }
}

/// One category sample. `stage` is set for sleep analysis; `value` carries the raw
/// category value for everything else (stand hours, where 0 means "stood").
public struct CategoryRecord: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var metric: HealthMetric
    public var value: Int
    public var stage: SleepStage?
    public var start: Date
    public var end: Date
    public var sourceName: String

    public init(id: UUID, metric: HealthMetric, value: Int, stage: SleepStage? = nil,
                start: Date, end: Date, sourceName: String) {
        self.id = id
        self.metric = metric
        self.value = value
        self.stage = stage
        self.start = start
        self.end = end
        self.sourceName = sourceName
    }

    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// A workout Apple's Workout app recorded. This module never creates one (spec §1).
public struct WorkoutRecord: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// A HealthKit activity-type name, e.g. `traditionalStrengthTraining`. Deliberately
    /// a string: the contract's closed sets do not cover activity types.
    public var activityType: String
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double?
    public var sourceName: String

    public init(id: UUID, activityType: String, start: Date, end: Date,
                activeEnergyKcal: Double? = nil, sourceName: String) {
        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.sourceName = sourceName
    }

    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }

    /// Minutes, rounded to the nearest minute, which is the unit the contract stores.
    public var durationMinutes: Int {
        Int((max(start, end).timeIntervalSince(start) / 60).rounded())
    }
}

/// A sample this module is about to write. Produced by the write layer as a value type
/// so a write can be asserted on in a test without a HealthKit store anywhere near it.
///
/// `syncIdentifier` is the idempotency key: HealthKit replaces a previously saved sample
/// that carries the same identifier instead of adding a second one, so a retried
/// mutation cannot double-log a meal. See `HealthWriter`.
public struct WriteSample: Hashable, Sendable {
    public var metric: HealthWriteMetric
    public var value: Double
    public var start: Date
    public var end: Date
    public var syncIdentifier: String
    public var syncVersion: Int

    public init(metric: HealthWriteMetric, value: Double, start: Date, end: Date,
                syncIdentifier: String, syncVersion: Int) {
        self.metric = metric
        self.value = value
        self.start = start
        self.end = end
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
    }
}
