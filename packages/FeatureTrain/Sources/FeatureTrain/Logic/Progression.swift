import AscensionCore
import AscensionEngines
import Foundation

/// The one manual training input, dated (spec §F2).
public struct LoggedTopSet: Hashable, Sendable, Identifiable {
    public var date: CalendarDate
    public var exerciseId: String
    public var weightKg: Double
    public var reps: Int
    public var sessionKind: SessionKind?

    public init(date: CalendarDate, exerciseId: String, weightKg: Double, reps: Int,
                sessionKind: SessionKind? = nil) {
        self.date = date
        self.exerciseId = exerciseId
        self.weightKg = weightKg
        self.reps = reps
        self.sessionKind = sessionKind
    }

    public var id: String { "\(date.rawValue)/\(exerciseId)" }

    /// The contract shape, for the rollup and the export.
    public var topSet: TopSet {
        TopSet(exerciseId: exerciseId, weightKg: weightKg, reps: reps)
    }
}

/// What to load an exercise with next session.
public struct ProgressionTarget: Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var last: LoggedTopSet?
    public var targetWeightKg: Double?
    /// Whether the target adds the increment, or holds the load for another session.
    public var advancing: Bool

    public init(exerciseId: String, last: LoggedTopSet? = nil,
                targetWeightKg: Double? = nil, advancing: Bool = false) {
        self.exerciseId = exerciseId
        self.last = last
        self.targetWeightKg = targetWeightKg
        self.advancing = advancing
    }

    public var id: String { exerciseId }
}

/// The program's progression rule, applied to the top set.
///
/// `rir2` is the spec's rule (§3): add the smallest increment once every set finishes
/// with two or more reps in reserve. The only evidence this app has is the top set's
/// weight and reps, so two reps in reserve means the lifter could have reached
/// `reps + 2` — and when that clears the top of the rep range, the load is no longer the
/// limit. Spec §F2's own example follows from exactly this: 11 reps in a 10–12 range is
/// 13 with the reserve, so 20 kg becomes 22.5 kg.
public enum Progression {

    public static func target(for slot: SessionExerciseEntry,
                              history: [LoggedTopSet],
                              settings: ProgressionSettings) -> ProgressionTarget {
        let last = history
            .filter { $0.exerciseId == slot.exerciseId }
            .max { $0.date < $1.date }
        guard let last else { return ProgressionTarget(exerciseId: slot.exerciseId) }
        let advances = advances(reps: last.reps, repsHigh: slot.repsHigh, rule: settings.rule)
        return ProgressionTarget(
            exerciseId: slot.exerciseId,
            last: last,
            targetWeightKg: advances ? last.weightKg + settings.incrementKg : last.weightKg,
            advancing: advances)
    }

    /// Every slot the session logs a top set for, in program order. The conditioning
    /// finisher is not one of them: a treadmill walk has no top set.
    public static func targets(for template: SessionTemplateEntry,
                               history: [LoggedTopSet],
                               settings: ProgressionSettings) -> [ProgressionTarget] {
        loggableSlots(in: template).map { target(for: $0, history: history, settings: settings) }
    }

    public static func loggableSlots(in template: SessionTemplateEntry) -> [SessionExerciseEntry] {
        template.exercises.filter { !$0.finisher }.sorted { $0.order < $1.order }
    }

    /// A slot with no rep range — a plank, a carry — holds its load: there is no rep
    /// count to read reserve from, so advancing on one would be guessing.
    static func advances(reps: Int, repsHigh: Int, rule: ProgressionRule) -> Bool {
        switch rule {
        case .rir2:
            guard repsHigh > 1 else { return false }
            return reps + 2 > repsHigh
        }
    }
}
