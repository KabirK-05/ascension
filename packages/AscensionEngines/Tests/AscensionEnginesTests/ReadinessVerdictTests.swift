import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("every verdict is reachable, and for the stated reason")
struct ReadinessVerdictTests {
    @Test("a well-rested day on a clear region trains as planned")
    func trainAsPlanned() {
        let assessment = ReadinessEngine.assess(Fix.input())
        #expect(assessment.verdict == .trainAsPlanned)
        #expect(assessment.score >= ReadinessThresholds.trainAsPlannedScore)
        #expect(assessment.confidence == .high)
        #expect(assessment.suggestedSession == nil)
        #expect(assessment.blockedRegions.isEmpty)
    }

    @Test("a middling day caps intensity")
    func capIntensity() {
        let assessment = ReadinessEngine.assess(
            Fix.input(asleepMinutes: 360,
                      consistencySd7Minutes: 60,
                      hrvSdnnMs: 34,
                      restingHrBpm: 62,
                      checkIn: Fix.checkIn(energy: 3)))
        #expect(assessment.verdict == .capIntensity)
        #expect(assessment.score >= ReadinessThresholds.activeRecoveryScore)
        #expect(assessment.score < ReadinessThresholds.trainAsPlannedScore)
        #expect(assessment.suggestedSession == nil)
    }

    @Test("a blocked region with a clear alternative swaps the session")
    func swapSession() {
        // The spec's own example: legs still sore on a Lower day, so do Upper.
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .lowerA, checkIn: Fix.checkIn(sore: [.quads])))
        #expect(assessment.verdict == .swapSession)
        #expect(assessment.blockedRegions[.lowerBody] == .sore)
        #expect(assessment.suggestedSession?.trainedRegions == [.upperBody])
        #expect(assessment.reasons.contains("quads sore"))
    }

    @Test("a wrecked day is active recovery whatever the plan says")
    func activeRecovery() {
        let assessment = ReadinessEngine.assess(
            Fix.input(asleepMinutes: 300,
                      consistencySd7Minutes: 100,
                      hrvSdnnMs: 30,
                      restingHrBpm: 68,
                      yesterdayLoadAu: 12_000,
                      checkIn: Fix.checkIn(energy: 1, mild: [.quads])))
        #expect(assessment.verdict == .activeRecovery)
        #expect(assessment.score < ReadinessThresholds.activeRecoveryScore)
        #expect(assessment.suggestedSession == nil)
    }

    @Test("the floor outranks a legal swap")
    func floorOutranksSwap() {
        // Upper is sore and Lower is clear, so a swap exists — but the body is below the
        // floor, and standing down beats training something else.
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .upperA,
                      asleepMinutes: 290,
                      consistencySd7Minutes: 110,
                      hrvSdnnMs: 29,
                      restingHrBpm: 70,
                      yesterdayLoadAu: 14_000,
                      checkIn: Fix.checkIn(energy: 1, sore: [.chest])))
        #expect(assessment.verdict == .activeRecovery)
        #expect(assessment.suggestedSession == nil)
    }

    @Test("a rest day follows the plan, however the day reads",
          arguments: [320, 400, 480])
    func restDayFollowsThePlan(asleepMinutes: Int) {
        // Nothing is prescribed, so there is nothing to cap, swap or stand down from.
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .rest,
                      asleepMinutes: asleepMinutes,
                      consistencySd7Minutes: 100,
                      hrvSdnnMs: 29,
                      restingHrBpm: 70,
                      checkIn: Fix.checkIn(energy: 1, sore: [.quads, .chest])))
        #expect(assessment.verdict == .trainAsPlanned)
        #expect(assessment.blockedRegions.isEmpty)
    }

    @Test("a day the program says nothing about is treated as a rest day")
    func unplannedDay() {
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: nil, checkIn: Fix.checkIn(sore: [.chest, .quads])))
        #expect(assessment.verdict == .trainAsPlanned)
    }

    @Test("conditioning loads no region, so it is never swapped away from")
    func zone2NeverBlocked() {
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .zone2, checkIn: Fix.checkIn(sore: [.chest, .quads])))
        #expect(assessment.blockedRegions.isEmpty)
        #expect(assessment.verdict != .swapSession)
    }

    @Test("a suggested session is named exactly when the verdict is a swap")
    func suggestionAccompaniesSwapOnly() {
        let cases = [Fix.input(),
                     Fix.input(planned: .lowerA, checkIn: Fix.checkIn(sore: [.quads])),
                     Fix.input(asleepMinutes: 300, consistencySd7Minutes: 110,
                               hrvSdnnMs: 29, restingHrBpm: 70,
                               checkIn: Fix.checkIn(energy: 1)),
                     Fix.blindInput()]
        for input in cases {
            let assessment = ReadinessEngine.assess(input)
            let isSwap = assessment.verdict == ReadinessVerdict.swapSession
            #expect((assessment.suggestedSession != nil) == isSwap)
        }
    }
}

@Suite("the assessment bridges to the synced contract")
struct ReadinessRollupTests {
    @Test("the rollup carries the score, the verdict and the two reasons")
    func rollupMatchesTheAssessment() {
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .lowerA, checkIn: Fix.checkIn(sore: [.quads])))
        let rollup = assessment.rollup

        #expect(rollup.score == assessment.score)
        #expect(rollup.verdict == assessment.verdict)
        #expect(rollup.reasons == assessment.reasons)
        #expect(rollup.reasons.count == 2)
    }

    @Test("the rollup encodes into the shape the contract documents")
    func rollupEncodes() throws {
        let rollup = ReadinessEngine.assess(Fix.input()).rollup
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try JSONSerialization.jsonObject(with: encoder.encode(rollup))

        guard let object = json as? [String: Any] else {
            Issue.record("a readiness rollup must encode as a JSON object")
            return
        }
        #expect(Set(object.keys) == ["score", "verdict", "reasons"])
        #expect(object["verdict"] as? String == ReadinessVerdict.trainAsPlanned.rawValue)
        #expect((object["reasons"] as? [String])?.count == 2)
    }

    @Test("an undated last session is reported as such, not as zero hours ago")
    func undatedSessionReason() {
        var input = Fix.input(lastTrainedAt: [.upperBody: Fix.stamp("2026-11-07T07:00:00-05:00")])
        input.clock = EngineClock(now: Fix.stamp("2026-11-09T07:00:60-05:00"),
                                  timezone: Seed.timezone)
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions[.upperBody] == .recencyUnknown)
        #expect(assessment.reasons.first == "upper body last session not dated")
    }

    @Test("three sore groups are listed with commas and an and")
    func threeSoreGroupsRead() {
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .lowerA,
                      checkIn: Fix.checkIn(sore: [.quads, .hamstrings, .glutes])))
        #expect(assessment.reasons.first == "quads, hamstrings and glutes sore")
    }
}
