import AscensionCore
import Foundation

// The flat, dated views of a `DayRollup`. `export.json` carries both the rollups and
// these projections (`docs/EXPORT_SCHEMA.md` §4) so a reader can take a whole day or a
// single entity without reshaping anything. They are *derived*, never supplied: there
// is one source for each number, so a projection cannot disagree with its rollup.
//
// Each row leads with `date` and then repeats the rollup's own field names verbatim.

/// A workout, stamped with the day it belongs to.
public struct WorkoutRow: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var healthKitId: String
    public var type: String
    public var startedAt: Timestamp
    public var endedAt: Timestamp
    public var durationMinutes: Int
    public var activeEnergyKcal: Double?
    public var hrAvgBpm: Int?
    public var hrMaxBpm: Int?
    public var timeInZonesMinutes: TimeInZonesMinutes
    public var source: String

    public init(date: CalendarDate, workout: WorkoutSummary) {
        self.date = date
        self.healthKitId = workout.healthKitId
        self.type = workout.type
        self.startedAt = workout.startedAt
        self.endedAt = workout.endedAt
        self.durationMinutes = workout.durationMinutes
        self.activeEnergyKcal = workout.activeEnergyKcal
        self.hrAvgBpm = workout.hrAvgBpm
        self.hrMaxBpm = workout.hrMaxBpm
        self.timeInZonesMinutes = workout.timeInZonesMinutes
        self.source = workout.source
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(healthKitId, forKey: .healthKitId)
        try container.encode(type, forKey: .type)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encodeNullable(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encodeNullable(hrAvgBpm, forKey: .hrAvgBpm)
        try container.encodeNullable(hrMaxBpm, forKey: .hrMaxBpm)
        try container.encode(timeInZonesMinutes, forKey: .timeInZonesMinutes)
        try container.encode(source, forKey: .source)
    }
}

/// A top set, stamped with the day it belongs to.
public struct TopSetRow: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var exerciseId: String
    public var weightKg: Double
    public var reps: Int

    public init(date: CalendarDate, topSet: TopSet) {
        self.date = date
        self.exerciseId = topSet.exerciseId
        self.weightKg = topSet.weightKg
        self.reps = topSet.reps
    }
}

/// A morning check-in, stamped with its day. Soreness stays nested so the key names
/// match the contract's `checkIn.soreness` object exactly.
public struct CheckInRow: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var energy: Int
    public var soreness: Soreness

    public init(date: CalendarDate, checkIn: CheckInRollup) {
        self.date = date
        self.energy = checkIn.energy
        self.soreness = checkIn.soreness
    }
}

/// A readiness score, stamped with its day.
public struct ReadinessRow: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var score: Int
    public var verdict: ReadinessVerdict
    public var reasons: [String]

    public init(date: CalendarDate, readiness: ReadinessRollup) {
        self.date = date
        self.score = readiness.score
        self.verdict = readiness.verdict
        self.reasons = readiness.reasons
    }
}

/// Last night's sleep, stamped with the day it was recorded against.
public struct SleepRow: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var asleepMinutes: Int?
    public var inBedMinutes: Int?
    public var consistencySd7Minutes: Double?

    public init(date: CalendarDate, sleep: SleepRollup) {
        self.date = date
        self.asleepMinutes = sleep.asleepMinutes
        self.inBedMinutes = sleep.inBedMinutes
        self.consistencySd7Minutes = sleep.consistencySd7Minutes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeNullable(asleepMinutes, forKey: .asleepMinutes)
        try container.encodeNullable(inBedMinutes, forKey: .inBedMinutes)
        try container.encodeNullable(consistencySd7Minutes, forKey: .consistencySd7Minutes)
    }
}

/// A body measurement, stamped with its day.
public struct WeightRow: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var weightKg: Double?
    public var weightAvg7Kg: Double?
    public var rateKgPerWeek: Double?
    public var bodyFatPct: Double?
    public var waistCm: Double?

    public init(date: CalendarDate, body: BodyRollup) {
        self.date = date
        self.weightKg = body.weightKg
        self.weightAvg7Kg = body.weightAvg7Kg
        self.rateKgPerWeek = body.rateKgPerWeek
        self.bodyFatPct = body.bodyFatPct
        self.waistCm = body.waistCm
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeNullable(weightKg, forKey: .weightKg)
        try container.encodeNullable(weightAvg7Kg, forKey: .weightAvg7Kg)
        try container.encodeNullable(rateKgPerWeek, forKey: .rateKgPerWeek)
        try container.encodeNullable(bodyFatPct, forKey: .bodyFatPct)
        try container.encodeNullable(waistCm, forKey: .waistCm)
    }
}

extension SleepRow {
    /// A sleep row is worth writing only when something was measured; `null` means *not
    /// measured*, so a row of nothing but nulls would assert a night that never existed.
    public var isMeasured: Bool {
        asleepMinutes != nil || inBedMinutes != nil || consistencySd7Minutes != nil
    }
}

extension WeightRow {
    public var isMeasured: Bool {
        weightKg != nil || weightAvg7Kg != nil || rateKgPerWeek != nil
            || bodyFatPct != nil || waistCm != nil
    }
}
