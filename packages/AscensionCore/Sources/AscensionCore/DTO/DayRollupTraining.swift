import Foundation

/// Minutes spent in each heart-rate zone during a workout.
public struct TimeInZonesMinutes: Codable, Hashable, Sendable {
    public var z1: Double
    public var z2: Double
    public var z3: Double
    public var z4: Double
    public var z5: Double

    public init(z1: Double = 0, z2: Double = 0, z3: Double = 0,
                z4: Double = 0, z5: Double = 0) {
        self.z1 = z1
        self.z2 = z2
        self.z3 = z3
        self.z4 = z4
        self.z5 = z5
    }

    public var total: Double { z1 + z2 + z3 + z4 + z5 }
}

/// A workout Apple recorded, mirrored by HealthKit UUID so re-reads are idempotent.
///
/// `type` is a HealthKit activity-type name and is deliberately an open string: the
/// contract's closed sets do not include it.
public struct WorkoutSummary: Codable, Hashable, Sendable {
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

    public init(healthKitId: String, type: String, startedAt: Timestamp, endedAt: Timestamp,
                durationMinutes: Int, activeEnergyKcal: Double? = nil, hrAvgBpm: Int? = nil,
                hrMaxBpm: Int? = nil,
                timeInZonesMinutes: TimeInZonesMinutes = TimeInZonesMinutes(),
                source: String) {
        self.healthKitId = healthKitId
        self.type = type
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
        self.timeInZonesMinutes = timeInZonesMinutes
        self.source = source
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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

/// The one manual training input: the heaviest set of an exercise that session.
public struct TopSet: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var weightKg: Double
    public var reps: Int

    public init(exerciseId: String, weightKg: Double, reps: Int) {
        self.exerciseId = exerciseId
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// Training for the day: what the program planned, what landed, and the load it cost.
public struct TrainingRollup: Codable, Hashable, Sendable {
    public var sessionPlanned: SessionKind?
    public var sessionDone: Bool
    public var loadAu: Double?
    public var workouts: [WorkoutSummary]
    public var topSets: [TopSet]

    public init(sessionPlanned: SessionKind? = nil, sessionDone: Bool = false,
                loadAu: Double? = nil, workouts: [WorkoutSummary] = [],
                topSets: [TopSet] = []) {
        self.sessionPlanned = sessionPlanned
        self.sessionDone = sessionDone
        self.loadAu = loadAu
        self.workouts = workouts
        self.topSets = topSets
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(sessionPlanned, forKey: .sessionPlanned)
        try container.encode(sessionDone, forKey: .sessionDone)
        try container.encodeNullable(loadAu, forKey: .loadAu)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(topSets, forKey: .topSets)
    }
}

extension TrainingRollup {
    /// `Σ durationMinutes × (hrAvgBpm / restingHrBpm)`, defined once in the contract so
    /// the app and the Worker can never compute it differently. `nil` when no workout
    /// carries the heart-rate data the formula needs.
    public static func loadAu(workouts: [WorkoutSummary], restingHrBpm: Int?) -> Double? {
        guard let restingHrBpm, restingHrBpm > 0 else { return nil }
        let contributions = workouts.compactMap { workout -> Double? in
            guard let hrAvgBpm = workout.hrAvgBpm else { return nil }
            return Double(workout.durationMinutes) * (Double(hrAvgBpm) / Double(restingHrBpm))
        }
        guard !contributions.isEmpty else { return nil }
        return contributions.reduce(0, +)
    }
}
