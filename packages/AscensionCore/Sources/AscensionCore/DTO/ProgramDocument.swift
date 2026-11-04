import Foundation

/// One day of the weekly plan. `weekday` is ISO-8601: Monday = 1.
public struct ProgramDayEntry: Codable, Hashable, Sendable {
    public var weekday: Int
    public var kind: SessionKind

    public init(weekday: Int, kind: SessionKind) {
        self.weekday = weekday
        self.kind = kind
    }
}

/// One exercise slot in a session. `exerciseId` references a free-exercise-db id.
public struct SessionExerciseEntry: Codable, Hashable, Sendable {
    public var order: Int
    public var exerciseId: String
    public var sets: Int
    public var repsLow: Int
    public var repsHigh: Int
    public var finisher: Bool

    public init(order: Int, exerciseId: String, sets: Int = 3,
                repsLow: Int = 10, repsHigh: Int = 12, finisher: Bool = false) {
        self.order = order
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.finisher = finisher
    }
}

/// A named session and its ordered exercises.
public struct SessionTemplateEntry: Codable, Hashable, Sendable {
    public var name: String
    public var exercises: [SessionExerciseEntry]

    public init(name: String, exercises: [SessionExerciseEntry]) {
        self.name = name
        self.exercises = exercises
    }
}

/// How load advances between sessions.
public struct ProgressionSettings: Codable, Hashable, Sendable {
    public var rule: ProgressionRule
    public var incrementKg: Double

    public init(rule: ProgressionRule, incrementKg: Double) {
        self.rule = rule
        self.incrementKg = incrementKg
    }
}

/// The conditioning finisher appended to lifting days. `daysPerWeek: 0` means none,
/// which is how the historical Zone 2 shape expresses itself.
public struct FinisherSettings: Codable, Hashable, Sendable {
    public var kind: FinisherKind
    public var minutes: Int
    public var inclinePct: Int
    public var daysPerWeek: Int

    public init(kind: FinisherKind, minutes: Int, inclinePct: Int, daysPerWeek: Int) {
        self.kind = kind
        self.minutes = minutes
        self.inclinePct = inclinePct
        self.daysPerWeek = daysPerWeek
    }
}

/// Deload state: same exercises, lighter and shorter, for one week.
public struct DeloadSettings: Codable, Hashable, Sendable {
    public var active: Bool
    public var loadFactor: Double
    public var volumeFactor: Double

    public init(active: Bool, loadFactor: Double, volumeFactor: Double) {
        self.active = active
        self.loadFactor = loadFactor
        self.volumeFactor = volumeFactor
    }
}

/// The `program` document (`docs/EXPORT_SCHEMA.md` §2.2).
///
/// `days` and `sessions` are separate on purpose: the week is a list of seven slots that
/// point at named sessions, so the same model holds the current four-day Upper/Lower
/// split and the historical Mon/Thu full-body + Wed/Sat Zone 2 shape (spec §3) without
/// either being hardcoded.
public struct ProgramDocument: Codable, Hashable, Sendable {
    public var version: Int
    public var updatedAt: Timestamp
    public var updatedBy: ActorKind
    public var name: String
    public var days: [ProgramDayEntry]
    public var sessions: [SessionKind: SessionTemplateEntry]
    public var progression: ProgressionSettings
    public var finisher: FinisherSettings
    public var deload: DeloadSettings

    public init(version: Int, updatedAt: Timestamp, updatedBy: ActorKind, name: String,
                days: [ProgramDayEntry], sessions: [SessionKind: SessionTemplateEntry],
                progression: ProgressionSettings, finisher: FinisherSettings,
                deload: DeloadSettings) {
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.name = name
        self.days = days
        self.sessions = sessions
        self.progression = progression
        self.finisher = finisher
        self.deload = deload
    }
}

extension ProgramDocument {
    public static let weekdayCount = 7

    public func kind(forWeekday weekday: Int) -> SessionKind? {
        days.first { $0.weekday == weekday }?.kind
    }

    public func session(forWeekday weekday: Int) -> SessionTemplateEntry? {
        guard let kind = kind(forWeekday: weekday) else { return nil }
        return sessions[kind]
    }

    /// Weekdays whose session carries a finisher slot.
    public var finisherWeekdays: [Int] {
        days.filter { day in
            sessions[day.kind]?.exercises.contains { $0.finisher } ?? false
        }
        .map(\.weekday)
        .sorted()
    }

    /// Everything the contract rejects a program write for.
    public func validate() throws {
        guard days.count == Self.weekdayCount else {
            throw DomainValidationError.programDayCountWrong(days.count)
        }
        let weekdays = days.map(\.weekday).sorted()
        guard weekdays == Array(1...Self.weekdayCount) else {
            throw DomainValidationError.programWeekdaysInvalid(weekdays)
        }
        let planned = Set(days.map(\.kind).filter(\.isTrainingDay))
        for kind in planned where sessions[kind] == nil {
            throw DomainValidationError.programSessionMissing(kind)
        }
        for (kind, template) in sessions {
            guard planned.contains(kind) else {
                throw DomainValidationError.programSessionUnreferenced(kind)
            }
            guard !template.exercises.isEmpty else {
                throw DomainValidationError.programSessionEmpty(kind)
            }
        }
        try validateRecovery()
    }

    /// Spec §F5: no two non-rest days training the same region may sit less than 48 h
    /// apart. Consecutive weekdays are 24 h apart, and the week wraps, so Sunday and
    /// Monday are checked too.
    private func validateRecovery() throws {
        for weekday in 1...Self.weekdayCount {
            let next = weekday == Self.weekdayCount ? 1 : weekday + 1
            guard let first = kind(forWeekday: weekday), let second = kind(forWeekday: next) else {
                continue
            }
            let shared = first.trainedRegions.intersection(second.trainedRegions)
            if let region = shared.sorted(by: { $0.rawValue < $1.rawValue }).first {
                throw DomainValidationError.muscleRegionTrainedTooSoon(
                    first: weekday, second: next, region: region)
            }
        }
    }
}
