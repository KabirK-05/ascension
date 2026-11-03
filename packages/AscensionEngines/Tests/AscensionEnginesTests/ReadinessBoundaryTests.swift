import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

/// Each threshold walked one step at a time, so a band can never quietly move.
@Suite("score bands and thresholds sit exactly where they are documented")
struct ReadinessBoundaryTests {
    @Test("the thresholds are the documented values")
    func thresholdsArePinned() {
        #expect(ReadinessThresholds.recoveryHours == 48)
        #expect(ReadinessThresholds.trainAsPlannedScore == 75)
        #expect(ReadinessThresholds.activeRecoveryScore == 40)
        #expect(ReadinessThresholds.highCoverage == 0.8)
        #expect(ReadinessThresholds.moderateCoverage == 0.5)
    }

    @Test("the train-as-planned band opens exactly at its threshold")
    func trainAsPlannedBoundary() {
        let crossing = crossing(threshold: ReadinessThresholds.trainAsPlannedScore,
                                dial: Fix.highDial)
        guard let crossing else {
            Issue.record("the high dial never crosses the train-as-planned threshold")
            return
        }
        #expect(crossing.below.score == ReadinessThresholds.trainAsPlannedScore - 1)
        #expect(crossing.below.verdict == .capIntensity)
        #expect(crossing.at.score == ReadinessThresholds.trainAsPlannedScore)
        #expect(crossing.at.verdict == .trainAsPlanned)
        #expect(crossing.above.verdict == .trainAsPlanned)
        #expect(crossing.at.confidence == .high)
    }

    @Test("the active-recovery floor closes exactly at its threshold")
    func activeRecoveryBoundary() {
        let crossing = crossing(threshold: ReadinessThresholds.activeRecoveryScore,
                                dial: Fix.lowDial)
        guard let crossing else {
            Issue.record("the low dial never crosses the active-recovery floor")
            return
        }
        #expect(crossing.below.score == ReadinessThresholds.activeRecoveryScore - 1)
        #expect(crossing.below.verdict == .activeRecovery)
        #expect(crossing.at.score == ReadinessThresholds.activeRecoveryScore)
        #expect(crossing.at.verdict != .activeRecovery)
        #expect(crossing.above.verdict != .activeRecovery)
    }

    @Test("the sleep factor tops out exactly at the 7.5 h target",
          arguments: [449, 450, 451])
    func sleepTargetBoundary(minutes: Int) {
        let target = Fix.goals.targets.sleepMinutes
        #expect(target == 450)
        let factor = ReadinessScore.factors(for: Fix.input(asleepMinutes: minutes))
            .first { $0.kind == .sleepDuration }
        guard let value = factor?.value else {
            Issue.record("the sleep factor must be measured at \(minutes) min")
            return
        }
        if minutes < target {
            #expect(value < 1)
        } else {
            #expect(value == 1)
        }
    }

    @Test("confidence bands sit on their coverage boundaries",
          arguments: [(0.0, ReadinessConfidence.low), (0.49, .low), (0.5, .moderate),
                      (0.79, .moderate), (0.8, .high), (1.0, .high)])
    func confidenceBoundaries(coverage: Double, expected: ReadinessConfidence) {
        #expect(ReadinessScore.confidence(coverage: coverage) == expected)
    }

    private struct Crossing {
        let below: ReadinessAssessment
        let at: ReadinessAssessment
        let above: ReadinessAssessment
    }

    /// Walks a dial minute by minute and returns the first triple that straddles
    /// `threshold`. The dial is monotonic in sleep, so the first crossing is the only one.
    private func crossing(threshold: Int,
                          dial: (Int) -> ReadinessInput) -> Crossing? {
        var previous: ReadinessAssessment?
        for minutes in 280...470 {
            let assessment = ReadinessEngine.assess(dial(minutes))
            if let previous, previous.score < threshold, assessment.score >= threshold {
                let above = ReadinessEngine.assess(dial(minutes + 1))
                return Crossing(below: previous, at: assessment, above: above)
            }
            previous = assessment
        }
        return nil
    }
}
