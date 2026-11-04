import Foundation
import SwiftData

/// A weekly training plan (spec §7).
///
/// The week is seven `ProgramDay` slots pointing at named `SessionTemplate`s, which is
/// what lets one model hold both the current Upper/Lower split and the historical
/// full-body + Zone 2 shape.
@Model
public final class Program {
    public var name: String = ""
    public var version: Int = 1
    public var updatedAt: String = ""
    public var updatedBy: ActorKind = ActorKind.device
    public var progressionRule: ProgressionRule = ProgressionRule.rir2
    public var incrementKg: Double = 2.5
    public var finisherKind: FinisherKind = FinisherKind.inclineWalk
    public var finisherMinutes: Int = 15
    public var finisherInclinePct: Int = 9
    public var finisherDaysPerWeek: Int = 0
    public var deloadActive: Bool = false
    public var deloadLoadFactor: Double = 0.6
    public var deloadVolumeFactor: Double = 0.5
    public var isActive: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
    public var days: [ProgramDay] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionTemplate.program)
    public var sessions: [SessionTemplate] = []

    public init(name: String, version: Int = 1, updatedAt: Timestamp,
                updatedBy: ActorKind = .device,
                progressionRule: ProgressionRule = .rir2, incrementKg: Double = 2.5,
                finisherKind: FinisherKind = .inclineWalk, finisherMinutes: Int = 15,
                finisherInclinePct: Int = 9, finisherDaysPerWeek: Int = 0,
                deloadActive: Bool = false, deloadLoadFactor: Double = 0.6,
                deloadVolumeFactor: Double = 0.5, isActive: Bool = false) {
        self.name = name
        self.version = version
        self.updatedAt = updatedAt.rawValue
        self.updatedBy = updatedBy
        self.progressionRule = progressionRule
        self.incrementKg = incrementKg
        self.finisherKind = finisherKind
        self.finisherMinutes = finisherMinutes
        self.finisherInclinePct = finisherInclinePct
        self.finisherDaysPerWeek = finisherDaysPerWeek
        self.deloadActive = deloadActive
        self.deloadLoadFactor = deloadLoadFactor
        self.deloadVolumeFactor = deloadVolumeFactor
        self.isActive = isActive
    }
}

/// One slot in the week. `weekday` is ISO-8601: Monday = 1.
@Model
public final class ProgramDay {
    public var weekday: Int = 1
    public var kind: SessionKind = SessionKind.rest
    public var program: Program?

    public init(weekday: Int, kind: SessionKind) {
        self.weekday = weekday
        self.kind = kind
    }
}

/// A named session and its ordered exercise slots.
@Model
public final class SessionTemplate {
    public var kind: SessionKind = SessionKind.rest
    public var name: String = ""
    public var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    public var exercises: [SessionExercise] = []

    public init(kind: SessionKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// One exercise slot. `exerciseId` references a free-exercise-db id rather than a
/// relationship, so a session survives the library being reimported.
@Model
public final class SessionExercise {
    public var order: Int = 1
    public var exerciseId: String = ""
    public var sets: Int = 3
    public var repsLow: Int = 10
    public var repsHigh: Int = 12
    public var finisher: Bool = false
    public var session: SessionTemplate?

    public init(order: Int, exerciseId: String, sets: Int = 3, repsLow: Int = 10,
                repsHigh: Int = 12, finisher: Bool = false) {
        self.order = order
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.finisher = finisher
    }
}

/// An exercise in the library (spec §7). Seeded for the program exercises; the full
/// free-exercise-db import is ASC-8.
@Model
public final class Exercise {
    @Attribute(.unique) public var id: String = ""
    public var name: String = ""
    public var primaryMuscles: [String] = []
    public var secondaryMuscles: [String] = []
    public var equipment: String?
    public var instructions: [String] = []
    public var imageRefs: [String] = []
    public var cues: [String] = []
    public var commonMistakes: [String] = []

    public init(id: String, name: String, primaryMuscles: [String] = [],
                secondaryMuscles: [String] = [], equipment: String? = nil,
                instructions: [String] = [], imageRefs: [String] = [],
                cues: [String] = [], commonMistakes: [String] = []) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instructions = instructions
        self.imageRefs = imageRefs
        self.cues = cues
        self.commonMistakes = commonMistakes
    }
}
