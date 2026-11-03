import AscensionCore
import Foundation

/// A workout Apple recorded, as this feature needs it.
///
/// `FeatureTrain` may not depend on `HealthBridge` (one feature, three allowed
/// dependencies — see `CLAUDE.md`), so the app shell maps a mirror into this through
/// `WorkoutSummary`, the contract shape both sides already speak.
public struct CompletedSession: Hashable, Sendable, Identifiable {
    public var id: String
    public var activityType: String
    public var start: Date
    public var end: Date
    public var durationMinutes: Int
    public var activeEnergyKcal: Double?
    public var hrAvgBpm: Int?
    public var hrMaxBpm: Int?
    public var timeInZones: TimeInZonesMinutes

    public init(id: String, activityType: String, start: Date, end: Date,
                durationMinutes: Int, activeEnergyKcal: Double? = nil,
                hrAvgBpm: Int? = nil, hrMaxBpm: Int? = nil,
                timeInZones: TimeInZonesMinutes = TimeInZonesMinutes()) {
        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
        self.timeInZones = timeInZones
    }

    /// `nil` when the summary's timestamps do not parse, which is a corrupt row rather
    /// than a session with no start.
    public init?(_ summary: WorkoutSummary) {
        guard let start = summary.startedAt.date, let end = summary.endedAt.date else { return nil }
        self.init(id: summary.healthKitId, activityType: summary.type, start: start, end: end,
                  durationMinutes: summary.durationMinutes,
                  activeEnergyKcal: summary.activeEnergyKcal, hrAvgBpm: summary.hrAvgBpm,
                  hrMaxBpm: summary.hrMaxBpm, timeInZones: summary.timeInZonesMinutes)
    }

    public var modality: TrainingModality { TrainingModality(activityType: activityType) }
}

/// What kind of work a recorded workout was.
///
/// The distinction is the whole of planned-vs-done matching: a lifting day is not
/// completed by a walk, however long the walk was.
public enum TrainingModality: String, Hashable, Sendable, CaseIterable {
    case strength
    case cardio
    case other

    /// HealthKit activity-type names, as `HealthBridge` spells them.
    public init(activityType: String) {
        if Self.strengthTypes.contains(activityType) {
            self = .strength
        } else if Self.cardioTypes.contains(activityType) {
            self = .cardio
        } else {
            self = .other
        }
    }

    private static let strengthTypes: Set<String> = [
        "traditionalStrengthTraining", "functionalStrengthTraining", "coreTraining",
        "highIntensityIntervalTraining"
    ]

    private static let cardioTypes: Set<String> = [
        "walking", "running", "hiking", "cycling", "rowing", "elliptical",
        "stairClimbing", "stairs", "jumpRope", "swimming", "mixedCardio"
    ]
}

extension SessionKind {
    /// What a recorded workout must be to complete this session. `nil` on a rest day,
    /// which nothing completes.
    public var requiredModality: TrainingModality? {
        switch self {
        case .upperA, .upperB, .lowerA, .lowerB, .fullBody: return .strength
        case .zone2: return .cardio
        case .rest: return nil
        }
    }
}
