import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

/// Spec §F5: "every verdict shows its top 2 reasons". `docs/DESIGN_RULES.md` §1 adds that
/// they are facts, not sentences about how the user should feel.
@Suite("reasons are two plain facts with units")
struct ReadinessReasonTests {
    @Test("the constraint that drives the verdict is the first reason")
    func constraintLeads() {
        let assessment = ReadinessEngine.assess(
            Fix.input(planned: .lowerA, checkIn: Fix.checkIn(sore: [.quads, .hamstrings])))
        #expect(assessment.verdict == .swapSession)
        #expect(assessment.reasons.first == "quads and hamstrings sore")
    }

    @Test("a region inside its recovery window is reported with the hours")
    func recencyIsReportedInHours() {
        let assessment = ReadinessEngine.assess(
            Fix.input(lastTrainedAt: [.upperBody: Fix.stamp("2026-11-08T09:00:00-05:00")]))
        #expect(assessment.reasons.first == "upper body trained 22 h ago")
    }

    @Test("a good day reports its two least-good facts")
    func goodDayStillExplainsItself() {
        // The §1 example in `docs/EXPORT_SCHEMA.md` reads
        // `["slept 7h42", "HRV near baseline"]` — the same two facts a good morning
        // surfaces here.
        let assessment = ReadinessEngine.assess(Fix.input(asleepMinutes: 462, hrvSdnnMs: 42))
        #expect(assessment.verdict == .trainAsPlanned)
        #expect(assessment.reasons.count == 2)
        #expect(assessment.reasons.contains("HRV near baseline"))
    }

    @Test("sleep is phrased in hours and minutes",
          arguments: zip([370, 462, 60, 0], ["slept 6h10", "slept 7h42", "slept 1h00", "slept 0h00"]))
    func sleepPhrasing(minutes: Int, expected: String) {
        let input = Fix.input(asleepMinutes: minutes)
        let factors = ReadinessScore.factors(for: input)
        let texts = ReadinessReasons.candidates(input: input, factors: factors,
                                                availabilities: [:], blocked: [:])
            .map(\.text)
        #expect(texts.contains(expected))
    }

    @Test("HRV is phrased as a signed percentage of baseline")
    func hrvPhrasing() {
        let input = Fix.input(hrvSdnnMs: 33.62, hrvBaseline: 41)
        let texts = reasonTexts(input)
        // 33.62 / 41 is 18% down. The spec writes exactly this sentence.
        #expect(texts.contains("HRV \u{2212}18% vs baseline"))

        let up = reasonTexts(Fix.input(hrvSdnnMs: 45.1, hrvBaseline: 41))
        #expect(up.contains("HRV +10% vs baseline"))
    }

    @Test("resting HR is phrased with its value and its delta")
    func restingHrPhrasing() {
        #expect(reasonTexts(Fix.input(restingHrBpm: 63, restingHrBaseline: 58))
            .contains("resting HR 63 bpm, +5 vs baseline"))
        #expect(reasonTexts(Fix.input(restingHrBpm: 55, restingHrBaseline: 58))
            .contains("resting HR 55 bpm, \u{2212}3 vs baseline"))
    }

    @Test("yesterday's load is phrased against a typical session")
    func loadPhrasing() {
        #expect(reasonTexts(Fix.input(yesterdayLoadAu: 9_600, loadBaseline: 6_000))
            .contains("load 9600 au yesterday, 1.6× typical"))
        #expect(reasonTexts(Fix.input(yesterdayLoadAu: 0)).contains("no training load yesterday"))
        #expect(reasonTexts(Fix.input(yesterdayLoadAu: nil))
            .contains("yesterday's load not measured"))
    }

    @Test("an absent reading is itself a reportable fact",
          arguments: ScoreFactorKind.allCases)
    func absenceIsReportable(kind: ScoreFactorKind) {
        let texts = reasonTexts(Fix.blindInput())
        #expect(texts.contains(ReadinessReasons.missingTextForTesting(kind)))
    }

    @Test("there are always exactly two reasons, whatever the input")
    func alwaysExactlyTwo() {
        let inputs = [Fix.input(),
                      Fix.blindInput(),
                      Fix.input(planned: .rest),
                      Fix.input(planned: nil, checkIn: nil),
                      Fix.input(checkIn: Fix.checkIn(sore: MuscleGroup.allCases)),
                      Fix.lowDial(asleepMinutes: 300),
                      Fix.highDial(asleepMinutes: 470)]
        for input in inputs {
            #expect(ReadinessEngine.assess(input).reasons.count == 2)
        }
    }

    @Test("the two reasons are distinct")
    func reasonsAreDistinct() {
        for minutes in stride(from: 280, through: 470, by: 10) {
            let reasons = ReadinessEngine.assess(Fix.lowDial(asleepMinutes: minutes)).reasons
            #expect(Set(reasons).count == 2)
        }
    }

    @Test("the same input always gives the same two reasons in the same order")
    func deterministic() {
        let input = Fix.input(planned: .lowerA,
                              asleepMinutes: 372,
                              consistencySd7Minutes: 55,
                              hrvSdnnMs: 35,
                              restingHrBpm: 61,
                              checkIn: Fix.checkIn(energy: 2, sore: [.quads], mild: [.back]))
        let first = ReadinessEngine.assess(input).reasons
        for _ in 0..<20 {
            #expect(ReadinessEngine.assess(input).reasons == first)
        }
    }

    @Test("no reason is advice, encouragement or a sentence")
    func factsNotAdvice() {
        let banned = ["should", "try", "consider", "you", "keep", "great", "nice", "let's",
                      "recommend", "take it easy", "push", "!"]
        var seen: Set<String> = []
        for minutes in stride(from: 280, through: 480, by: 20) {
            for energy in 1...5 {
                let input = Fix.input(asleepMinutes: minutes,
                                      checkIn: Fix.checkIn(energy: energy, mild: [.core]))
                seen.formUnion(ReadinessEngine.assess(input).reasons)
            }
        }
        seen.formUnion(ReadinessEngine.assess(Fix.blindInput()).reasons)
        #expect(!seen.isEmpty)
        for reason in seen {
            let lower = reason.lowercased()
            for word in banned {
                #expect(!lower.contains(word), "reason \"\(reason)\" reads as advice")
            }
            #expect(!reason.hasSuffix("."))
        }
    }

    private func reasonTexts(_ input: ReadinessInput) -> [String] {
        ReadinessReasons.candidates(input: input,
                                    factors: ReadinessScore.factors(for: input),
                                    availabilities: SessionLegality.availabilities(input: input),
                                    blocked: [:])
            .map(\.text)
    }
}
