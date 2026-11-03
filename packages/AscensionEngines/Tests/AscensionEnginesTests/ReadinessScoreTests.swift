import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("the score is a weighted mean over the factors that were measured")
struct ReadinessScoreTests {
    @Test("the seven factors' weights sum to one hundred")
    func weightsSumToOneHundred() {
        let total = ScoreFactorKind.allCases.reduce(0) { $0 + $1.weight }
        #expect(total == 100)
        #expect(ScoreFactorKind.allCases.count == 7)
    }

    @Test("every factor at full marks is one hundred, at zero marks is zero")
    func extremes() {
        #expect(ReadinessScore.score(from: factors(allAt: 1)).score == 100)
        #expect(ReadinessScore.score(from: factors(allAt: 0)).score == 0)
        #expect(ReadinessScore.score(from: factors(allAt: 1)).coverage == 1)
    }

    @Test("an unmeasured factor leaves both halves of the mean, rather than scoring zero")
    func renormalisesOverMeasuredWeight() {
        // Sleep (25) at full marks, everything else unmeasured: the mean is over 25, not
        // over 100, so the score is 100 and the coverage is a quarter.
        var all = factors(allAt: nil)
        all = all.map { factor in
            factor.kind == .sleepDuration
                ? ScoreFactor(kind: factor.kind, weight: factor.weight, value: 1)
                : factor
        }
        let result = ReadinessScore.score(from: all)
        #expect(result.score == 100)
        #expect(abs(result.coverage - 0.25) < 0.0001)
    }

    @Test("with nothing measured the score is the neutral midpoint and coverage is zero")
    func nothingMeasured() {
        let result = ReadinessScore.score(from: factors(allAt: nil))
        #expect(result.score == ReadinessThresholds.unmeasuredScore)
        #expect(result.coverage == 0)
    }

    @Test("the score is clamped into 0...100 even if a factor misbehaves")
    func clamping() {
        let tooHigh = [ScoreFactor(kind: .sleepDuration, weight: 25, value: 4)]
        let tooLow = [ScoreFactor(kind: .sleepDuration, weight: 25, value: -4)]
        #expect(ReadinessScore.score(from: tooHigh).score == 100)
        #expect(ReadinessScore.score(from: tooLow).score == 0)
    }

    @Test("the ramp clamps at both ends and runs linearly between them")
    func rampShape() {
        #expect(ReadinessScore.ramp(0.5, worst: 1, best: 2) == 0)
        #expect(ReadinessScore.ramp(1.0, worst: 1, best: 2) == 0)
        #expect(ReadinessScore.ramp(1.5, worst: 1, best: 2) == 0.5)
        #expect(ReadinessScore.ramp(2.0, worst: 1, best: 2) == 1)
        #expect(ReadinessScore.ramp(9.0, worst: 1, best: 2) == 1)
        // Reversed, for the metrics where lower is better.
        #expect(ReadinessScore.ramp(0, worst: 8, best: 0) == 1)
        #expect(ReadinessScore.ramp(4, worst: 8, best: 0) == 0.5)
        #expect(ReadinessScore.ramp(8, worst: 8, best: 0) == 0)
    }

    @Test("more sleep never lowers the score, and more HRV never lowers it either")
    func monotonicity() {
        let sleepScores = stride(from: 300, through: 480, by: 15).map {
            ReadinessEngine.assess(Fix.input(asleepMinutes: $0)).score
        }
        #expect(sleepScores == sleepScores.sorted())

        let hrvScores = stride(from: 28.0, through: 48.0, by: 2).map {
            ReadinessEngine.assess(Fix.input(hrvSdnnMs: $0)).score
        }
        #expect(hrvScores == hrvScores.sorted())
    }

    @Test("more soreness never raises the score")
    func sorenessIsMonotonic() {
        let groups: [MuscleGroup] = [.chest, .back, .shoulders, .arms]
        let scores = (0...groups.count).map { count in
            ReadinessEngine.assess(Fix.input(checkIn: Fix.checkIn(sore: Array(groups.prefix(count)))))
                .score
        }
        #expect(scores == scores.sorted(by: >))
    }

    @Test("the energy scale spans the full range it is given",
          arguments: zip([1, 2, 3, 4, 5], [0.0, 0.25, 0.5, 0.75, 1.0]))
    func energyScale(energy: Int, expected: Double) {
        let factors = ReadinessScore.factors(for: Fix.input(checkIn: Fix.checkIn(energy: energy)))
        let value = factors.first { $0.kind == .energy }?.value
        #expect(value != nil)
        #expect(abs((value ?? -1) - expected) < 0.0001)
    }

    private func factors(allAt value: Double?) -> [ScoreFactor] {
        ScoreFactorKind.allCases.map {
            ScoreFactor(kind: $0, weight: $0.weight, value: value)
        }
    }
}
