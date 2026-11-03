import Foundation

/// The kind of session a program day prescribes.
///
/// A closed set (`docs/EXPORT_SCHEMA.md` §1). `null` in JSON is modelled by `Optional`,
/// never by a case, so an unknown string fails to decode instead of silently becoming
/// "rest".
public enum SessionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case upperA
    case upperB
    case lowerA
    case lowerB
    case fullBody
    case zone2
    case rest
}

extension SessionKind: CodingKeyRepresentable {}

/// The regions a session loads, for the "same group never under 48 h apart" rule
/// (spec §3, §F5). Conditioning work loads no lifting region.
public enum MuscleRegion: String, Codable, Hashable, Sendable, CaseIterable {
    case upperBody
    case lowerBody
}

extension SessionKind {
    public var trainedRegions: Set<MuscleRegion> {
        switch self {
        case .upperA, .upperB: return [.upperBody]
        case .lowerA, .lowerB: return [.lowerBody]
        case .fullBody: return [.upperBody, .lowerBody]
        case .zone2, .rest: return []
        }
    }

    public var isTrainingDay: Bool { self != .rest }
}

/// What the readiness engine tells the user to do today. A closed set.
public enum ReadinessVerdict: String, Codable, Hashable, Sendable, CaseIterable {
    case trainAsPlanned
    case capIntensity
    case swapSession
    case activeRecovery
}

/// Morning check-in soreness, per muscle group. A closed set.
public enum SorenessLevel: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case mild
    case sore
}

/// The eight groups the morning check-in asks about.
public enum MuscleGroup: String, Codable, Hashable, Sendable, CaseIterable {
    case chest
    case back
    case shoulders
    case arms
    case quads
    case hamstrings
    case glutes
    case core
}

/// Which meal a log belongs to. A closed set.
public enum MealKind: String, Codable, Hashable, Sendable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
}

/// Who wrote a document or appended a mutation.
public enum ActorKind: String, Codable, Hashable, Sendable, CaseIterable {
    case muse
    case device
    case system
}

/// Whether Muse's writes apply directly or land as proposals.
public enum MuseWriteMode: String, Codable, Hashable, Sendable, CaseIterable {
    case apply
    case propose
}

/// The progression rule a program advances load by.
public enum ProgressionRule: String, Codable, Hashable, Sendable, CaseIterable {
    /// Add the increment once every set finishes with 2+ reps in reserve.
    case rir2
}

/// The kind of conditioning finisher a program appends to lifting days.
public enum FinisherKind: String, Codable, Hashable, Sendable, CaseIterable {
    case inclineWalk
}

/// Where a food item's macros came from (spec §7).
public enum FoodSource: String, Codable, Hashable, Sendable, CaseIterable {
    case staple
    case off = "OFF"
    case usda = "USDA"
    case custom
}

/// Every kind of mutation the write log accepts (`docs/EXPORT_SCHEMA.md` §3).
public enum MutationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case setTargets = "set_targets"
    case updateProgram = "update_program"
    case setStaples = "set_staples"
    case setFlag = "set_flag"
    case acceptSuggestion = "accept_suggestion"
    case logMeal = "log_meal"
    case logWater = "log_water"
    case logTopSet = "log_top_set"
    case logCheckIn = "log_checkin"
    case scheduleWorkout = "schedule_workout"
    case triggerExport = "trigger_export"
}

extension MutationKind {
    /// Tier 1 mutations are applied by the Worker; Tier 2 are applied by the device,
    /// which is why a Tier-2 tool may only ever answer `pending_device_apply`.
    public var tier: Int {
        switch self {
        case .setTargets, .updateProgram, .setStaples, .setFlag, .acceptSuggestion:
            return 1
        case .logMeal, .logWater, .logTopSet, .logCheckIn, .scheduleWorkout, .triggerExport:
            return 2
        }
    }
}
