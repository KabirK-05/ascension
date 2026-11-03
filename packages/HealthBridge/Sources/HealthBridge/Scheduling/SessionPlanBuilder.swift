import AscensionCore
import Foundation

/// Turns a program session into the plan the Watch is sent (spec §F2).
///
/// A lifting session is one open-goal step per exercise: WorkoutKit can express time,
/// distance and energy, and none of those is "3 × 10 at 20 kg", so the plan carries the
/// names and the lifter ends each step. The incline-walk finisher *is* expressible —
/// it is a timed interval — and Zone 2 work carries a heart-rate target, which is the
/// whole reason that session exists.
public enum SessionPlanBuilder {

    /// The plan for one program day. `nil` for a rest day, which has nothing to send.
    public static func plan(kind: SessionKind,
                            template: SessionTemplateEntry,
                            finisher: FinisherSettings,
                            exerciseNames: [String: String] = [:],
                            zones: HeartRateZones? = nil) -> SessionPlan? {
        guard kind != .rest else { return nil }
        if kind == .zone2 {
            return conditioningPlan(displayName: template.name, finisher: finisher, zones: zones)
        }
        let lifting = template.exercises.filter { !$0.finisher }.sorted { $0.order < $1.order }
        guard !lifting.isEmpty else { return nil }

        var blocks = lifting.map { slot in
            SessionPlanBlock(
                steps: [SessionPlanStep(displayName: exerciseNames[slot.exerciseId] ?? slot.exerciseId)],
                iterations: max(1, slot.sets))
        }
        if template.exercises.contains(where: \.finisher) {
            blocks.append(contentsOf: finisherBlocks(finisher, zones: zones))
        }
        return SessionPlan(displayName: template.name,
                           activity: .traditionalStrengthTraining,
                           blocks: blocks)
    }

    /// A standalone conditioning session: one timed walk held in Zone 2.
    private static func conditioningPlan(displayName: String,
                                         finisher: FinisherSettings,
                                         zones: HeartRateZones?) -> SessionPlan {
        SessionPlan(displayName: displayName,
                    activity: .walking,
                    blocks: [SessionPlanBlock(
                        steps: [SessionPlanStep(displayName: displayName,
                                                goal: .minutes(Double(max(1, finisher.minutes))),
                                                heartRate: zone2Target(zones))])])
    }

    /// The finisher appended to a lifting day: a timed interval, held in Zone 2.
    private static func finisherBlocks(_ finisher: FinisherSettings,
                                       zones: HeartRateZones?) -> [SessionPlanBlock] {
        guard finisher.minutes > 0 else { return [] }
        return [SessionPlanBlock(
            steps: [SessionPlanStep(displayName: finisher.kind.planStepName,
                                    goal: .minutes(Double(finisher.minutes)),
                                    heartRate: zone2Target(zones))])]
    }

    /// Zone 2 as bpm when this app's own bounds are known, and as a zone number when they
    /// are not — never as nothing, because an unverifiable Zone 2 session is the failure
    /// spec §F2 asks the debrief to catch.
    static func zone2Target(_ zones: HeartRateZones?) -> SessionHeartRateTarget {
        guard let zones else { return .zone(2) }
        let lower = Int(zones.lowerBounds[1].rounded())
        let upper = max(lower + 1, Int(zones.lowerBounds[2].rounded()) - 1)
        return .bpmRange(lower...upper)
    }
}

extension FinisherKind {
    /// What the step is called on the Watch. A name, not a sentence.
    var planStepName: String {
        switch self {
        case .inclineWalk: return "Incline walk"
        }
    }
}
