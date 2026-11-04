import AscensionCore
import Foundation

/// Readiness (spec §F5). A pure function from ``ReadinessInput`` to a score, a verdict
/// and the two facts behind it.
///
/// The division of labour is deliberate and is the thing to preserve when these rules
/// change: ``SessionLegality`` decides *what may be trained* and nothing else may
/// override it; ``ReadinessScore`` decides *how hard*. A low score can never unlock a
/// region inside its 48 h window, and a high score can never either.
///
/// Output is training guidance, not medical advice or diagnosis (spec §12).
public enum ReadinessEngine {
    /// Today's assessment.
    public static func assess(_ input: ReadinessInput) -> ReadinessAssessment {
        let factors = ReadinessScore.factors(for: input)
        let (score, coverage) = ReadinessScore.score(from: factors)
        let confidence = ReadinessScore.confidence(coverage: coverage)
        let availabilities = SessionLegality.availabilities(input: input)
        let blocked = input.plannedSession.map {
            SessionLegality.blockedRegions(of: $0, availabilities: availabilities)
        } ?? [:]

        let decision = decide(input: input, score: score, confidence: confidence,
                              availabilities: availabilities, blocked: blocked)
        let reasons = ReadinessReasons.topTwo(input: input, factors: factors,
                                              availabilities: availabilities, blocked: blocked)

        return ReadinessAssessment(score: score,
                                   verdict: decision.verdict,
                                   reasons: reasons,
                                   confidence: confidence,
                                   coverage: coverage,
                                   suggestedSession: decision.suggestedSession,
                                   blockedRegions: blocked)
    }

    private struct Decision {
        let verdict: ReadinessVerdict
        let suggestedSession: SessionKind?
    }

    /// The verdict ladder, in the order the rules apply.
    private static func decide(input: ReadinessInput,
                               score: Int,
                               confidence: ReadinessConfidence,
                               availabilities: [MuscleRegion: RegionAvailability],
                               blocked: [MuscleRegion: RegionBlockReason]) -> Decision {
        // A rest day, or a day the program says nothing about, prescribes no load. There
        // is nothing to cap, swap or stand down from, whatever the score reads.
        guard let planned = input.plannedSession, planned.isTrainingDay else {
            return Decision(verdict: .trainAsPlanned, suggestedSession: nil)
        }

        // Below the floor nothing is trained, so a swap would be the wrong answer even
        // when one is legal.
        if score < ReadinessThresholds.activeRecoveryScore {
            return Decision(verdict: .activeRecovery, suggestedSession: nil)
        }

        // The hard constraint. A swap is offered only when it is itself legal; when the
        // program has no legal lifting session left, the day stands down.
        if !blocked.isEmpty {
            guard let swap = SessionLegality.swap(for: planned,
                                                  among: input.programSessions,
                                                  availabilities: availabilities) else {
                return Decision(verdict: .activeRecovery, suggestedSession: nil)
            }
            return Decision(verdict: .swapSession, suggestedSession: swap)
        }

        // Too little was measured to say "train as planned" and mean it (spec §F5).
        if confidence == .low {
            return Decision(verdict: .capIntensity, suggestedSession: nil)
        }

        // Core belongs to no region, so it cannot block a session outright — but a sore
        // core loads every lift, so it holds the day back to a capped one.
        if isCoreSore(input) {
            return Decision(verdict: .capIntensity, suggestedSession: nil)
        }

        if score >= ReadinessThresholds.trainAsPlannedScore {
            return Decision(verdict: .trainAsPlanned, suggestedSession: nil)
        }
        return Decision(verdict: .capIntensity, suggestedSession: nil)
    }

    private static func isCoreSore(_ input: ReadinessInput) -> Bool {
        guard let soreness = input.checkIn?.soreness else { return false }
        return SessionLegality.unregionedGroups.contains { soreness.level(for: $0) == .sore }
    }
}
