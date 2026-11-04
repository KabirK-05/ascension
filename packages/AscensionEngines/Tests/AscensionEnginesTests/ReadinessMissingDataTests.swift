import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

/// `null` means *not measured* and never zero (`docs/EXPORT_SCHEMA.md`). Spec §F5 adds
/// that a missing input must narrow confidence rather than produce a wrong confident
/// verdict — so these are the tests that stop a blank morning from reading as a terrible
/// one.
@Suite("a missing measurement narrows confidence instead of scoring zero")
struct ReadinessMissingDataTests {
    @Test("a day with nothing measured is neither confident nor condemned")
    func nothingMeasured() {
        let assessment = ReadinessEngine.assess(Fix.blindInput())
        #expect(assessment.coverage == 0)
        #expect(assessment.confidence == .low)
        #expect(assessment.score == ReadinessThresholds.unmeasuredScore)
        #expect(assessment.verdict == .capIntensity)
        #expect(assessment.reasons.count == 2)
    }

    @Test("absent HRV does not score as a collapsed HRV")
    func absentHrvIsNotZero() {
        let withHrv = ReadinessEngine.assess(Fix.input())
        let withoutHrv = ReadinessEngine.assess(Fix.input(hrvSdnnMs: nil))
        let collapsedHrv = ReadinessEngine.assess(Fix.input(hrvSdnnMs: 1))

        #expect(withoutHrv.coverage < withHrv.coverage)
        #expect(withoutHrv.score > collapsedHrv.score)
        // Dropping the term cannot move the score below the band a measured-good day sits
        // in: the remaining factors are still good.
        #expect(withoutHrv.verdict == .trainAsPlanned)
    }

    @Test("absent sleep does not score as no sleep")
    func absentSleepIsNotZero() {
        let withoutSleep = ReadinessEngine.assess(Fix.input(asleepMinutes: nil))
        let noSleep = ReadinessEngine.assess(Fix.input(asleepMinutes: 0))
        #expect(withoutSleep.score > noSleep.score)
        // An unrecorded night still trains as planned on the strength of the other six
        // signals; a recorded night of no sleep does not.
        #expect(withoutSleep.verdict == .trainAsPlanned)
        #expect(noSleep.verdict == .capIntensity)
    }

    @Test("a baseline without a reading, and a reading without a baseline, both abstain")
    func halfAPairIsNoPair() {
        let noReading = ReadinessScore.factors(for: Fix.input(hrvSdnnMs: nil))
        let noBaseline = ReadinessScore.factors(for: Fix.input(hrvBaseline: nil))
        #expect(noReading.first { $0.kind == .hrv }?.value == nil)
        #expect(noBaseline.first { $0.kind == .hrv }?.value == nil)
    }

    @Test("a zero baseline abstains rather than dividing by it")
    func zeroBaselineAbstains() {
        let factors = ReadinessScore.factors(for: Fix.input(hrvBaseline: 0, loadBaseline: 0))
        #expect(factors.first { $0.kind == .hrv }?.value == nil)
        #expect(factors.first { $0.kind == .yesterdayLoad }?.value == nil)
    }

    @Test("no check-in means soreness is unknown, not none")
    func noCheckInIsNotNoSoreness() {
        let factors = ReadinessScore.factors(for: Fix.input(checkIn: nil))
        #expect(factors.first { $0.kind == .soreness }?.value == nil)
        #expect(factors.first { $0.kind == .energy }?.value == nil)
        #expect(ReadinessEngine.assess(Fix.input(checkIn: nil)).reasons.contains("no check-in"))
    }

    @Test("a skipped check-in does not block training on its own")
    func skippedCheckInDoesNotBlock() {
        // Unknown soreness is not soreness. The ten-second check-in may simply not have
        // happened, and refusing to train until it does would make a habit surface a
        // gate. The 48 h rule still applies, from history; the score simply abstains on
        // soreness and energy, which costs 15 points of coverage.
        let assessment = ReadinessEngine.assess(Fix.input(checkIn: nil))
        #expect(assessment.blockedRegions.isEmpty)
        #expect(abs(assessment.coverage - 0.85) < 0.0001)
        #expect(assessment.confidence == .high)
        #expect(assessment.verdict == .trainAsPlanned)
    }

    @Test("a rest day's zero load and an unmeasured load are different things")
    func zeroLoadIsNotMissingLoad() {
        let rested = ReadinessScore.factors(for: Fix.input(yesterdayLoadAu: 0))
        let unknown = ReadinessScore.factors(for: Fix.input(yesterdayLoadAu: nil))
        #expect(rested.first { $0.kind == .yesterdayLoad }?.value == 1)
        #expect(unknown.first { $0.kind == .yesterdayLoad }?.value == nil)
    }

    @Test("every optional measurement can go missing on its own without a crash",
          arguments: ScoreFactorKind.allCases)
    func eachMeasurementCanBeMissing(kind: ScoreFactorKind) {
        let assessment = ReadinessEngine.assess(input(missing: kind))
        #expect((0...100).contains(assessment.score))
        #expect(assessment.reasons.count == 2)
        #expect(assessment.coverage < 1)
    }

    @Test("low coverage holds the verdict back from train-as-planned")
    func lowCoverageCaps() {
        // Only sleep is measured: a perfect night, 25% coverage. The score is 100 and the
        // verdict is still capped, because one signal is not a verdict.
        let assessment = ReadinessEngine.assess(
            Fix.input(asleepMinutes: 480,
                      consistencySd7Minutes: nil,
                      hrvSdnnMs: nil,
                      hrvBaseline: nil,
                      restingHrBpm: nil,
                      restingHrBaseline: nil,
                      yesterdayLoadAu: nil,
                      loadBaseline: nil,
                      checkIn: nil))
        #expect(assessment.score == 100)
        #expect(assessment.confidence == .low)
        #expect(assessment.verdict == .capIntensity)
    }

    @Test("the hard constraint still applies when nothing is measured")
    func constraintSurvivesBlindness() {
        var input = Fix.blindInput()
        input.lastTrainedAt = [.upperBody: Fix.stamp("2026-11-08T19:00:00-05:00")]
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions[.upperBody] == .withinRecoveryWindow)
        #expect(assessment.verdict == .swapSession)
        #expect(assessment.suggestedSession?.trainedRegions == [.lowerBody])
    }

    private func input(missing kind: ScoreFactorKind) -> ReadinessInput {
        switch kind {
        case .sleepDuration: return Fix.input(asleepMinutes: nil)
        case .sleepConsistency: return Fix.input(consistencySd7Minutes: nil)
        case .hrv: return Fix.input(hrvSdnnMs: nil)
        case .restingHr: return Fix.input(restingHrBpm: nil)
        case .yesterdayLoad: return Fix.input(yesterdayLoadAu: nil)
        case .soreness, .energy: return Fix.input(checkIn: nil)
        }
    }
}
