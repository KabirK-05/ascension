import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

/// One readiness scenario, named so a failing case says what it was.
struct ReadinessScenario: Sendable, CustomTestStringConvertible {
    let planned: SessionKind?
    let sleep: Int?
    let hrv: Double?
    let soreness: [MuscleGroup]
    let recency: Recency

    enum Recency: String, Sendable, CaseIterable {
        case neverTrained
        case upperYesterday
        case lowerYesterday
        case bothYesterday
        case upperLastWeek

        var stamps: [MuscleRegion: Timestamp] {
            let yesterday = Timestamp.literal("2026-11-08T19:00:00-05:00")
            let lastWeek = Timestamp.literal("2026-11-02T19:00:00-05:00")
            switch self {
            case .neverTrained: return [:]
            case .upperYesterday: return [.upperBody: yesterday]
            case .lowerYesterday: return [.lowerBody: yesterday]
            case .bothYesterday: return [.upperBody: yesterday, .lowerBody: yesterday]
            case .upperLastWeek: return [.upperBody: lastWeek]
            }
        }
    }

    var testDescription: String {
        let sleepText = sleep.map(String.init) ?? "nil"
        let hrvText = hrv.map { Phrase.decimal($0) } ?? "nil"
        let soreText = soreness.isEmpty ? "clear" : soreness.map(\.rawValue).joined(separator: "+")
        return "\(planned?.rawValue ?? "unplanned")/sleep \(sleepText)/hrv \(hrvText)/"
            + "\(soreText)/\(recency.rawValue)"
    }

    var input: ReadinessInput {
        Fix.input(planned: planned,
                  asleepMinutes: sleep,
                  hrvSdnnMs: hrv,
                  checkIn: Fix.checkIn(energy: 3, sore: soreness),
                  lastTrainedAt: recency.stamps)
    }

    /// A deterministic grid of realistic mornings — no randomness, so a failure is
    /// reproducible from its name alone.
    static let grid: [ReadinessScenario] = {
        let planned: [SessionKind?] = [.upperA, .lowerA, .fullBody, .zone2, .rest, nil]
        let sleeps: [Int?] = [nil, 300, 390, 462]
        let hrvs: [Double?] = [nil, 30, 41, 48]
        let soreness: [[MuscleGroup]] = [[], [.quads], [.chest], [.core],
                                         [.chest, .quads], MuscleGroup.allCases]
        return planned.flatMap { plan in
            sleeps.flatMap { sleep in
                hrvs.flatMap { hrv in
                    soreness.flatMap { sore in
                        Recency.allCases.map {
                            ReadinessScenario(planned: plan, sleep: sleep, hrv: hrv,
                                              soreness: sore, recency: $0)
                        }
                    }
                }
            }
        }
    }()
}

/// The properties that must hold for *every* input, not just the ones a test imagined.
@Suite("readiness invariants hold across the whole input grid")
struct ReadinessInvariantTests {
    @Test("the grid is big enough to be worth calling a grid")
    func gridSize() {
        #expect(ReadinessScenario.grid.count == 2_880)
    }

    @Test("score, reasons, swap legality and coverage hold everywhere",
          arguments: ReadinessScenario.grid)
    func invariants(scenario: ReadinessScenario) {
        let input = scenario.input
        let assessment = ReadinessEngine.assess(input)
        let availabilities = SessionLegality.availabilities(input: input)

        // The score is a percentage.
        #expect((0...100).contains(assessment.score))
        #expect((0...1).contains(assessment.coverage))

        // Spec §F5: exactly two reasons, always.
        #expect(assessment.reasons.count == 2)
        #expect(Set(assessment.reasons).count == 2)
        #expect(assessment.reasons.allSatisfy { !$0.isEmpty })

        // A swap is named exactly when the verdict is a swap, and is itself legal.
        #expect((assessment.suggestedSession != nil) == (assessment.verdict == .swapSession))
        if let swap = assessment.suggestedSession {
            #expect(SessionLegality.isLegal(swap, availabilities: availabilities))
            #expect(swap != input.plannedSession)
            #expect(swap.isTrainingDay)
            #expect(!swap.trainedRegions.isEmpty)
            #expect(input.programSessions.contains(swap))
        }

        // The hard rule, stated as a property: nothing the engine recommends loads a
        // region that may not be loaded.
        for region in recommendedRegions(assessment, planned: input.plannedSession) {
            guard let availability = availabilities[region] else { continue }
            #expect(availability.isTrainable, "recommended a region that is not trainable")
            #expect(!availability.isSore)
            #expect(!availability.isWithinRecoveryWindow)
        }

        // Confidence is a function of coverage and nothing else.
        #expect(assessment.confidence == ReadinessScore.confidence(coverage: assessment.coverage))

        // Below the floor nothing is ever recommended.
        if assessment.score < ReadinessThresholds.activeRecoveryScore,
           input.plannedSession?.isTrainingDay == true {
            #expect(assessment.verdict == .activeRecovery)
        }

        // Low confidence never produces a confident verdict on a training day.
        if assessment.confidence == .low, input.plannedSession?.isTrainingDay == true {
            #expect(assessment.verdict != .trainAsPlanned)
        }
    }

    @Test("a sore region is never recommended, across the grid")
    func soreRegionsAreNeverRecommended() {
        for scenario in ReadinessScenario.grid {
            let input = scenario.input
            let assessment = ReadinessEngine.assess(input)
            let availabilities = SessionLegality.availabilities(input: input)
            let sore = Set(availabilities.values.filter(\.isSore).map(\.region))
            let recommended = recommendedRegions(assessment, planned: input.plannedSession)
            #expect(sore.isDisjoint(with: recommended),
                    Comment(rawValue: "\(scenario.testDescription) recommended a sore region"))
        }
    }

    @Test("the engine is a pure function of its input, across the grid")
    func deterministic() {
        for scenario in ReadinessScenario.grid {
            let first = ReadinessEngine.assess(scenario.input)
            let second = ReadinessEngine.assess(scenario.input)
            #expect(first == second, Comment(rawValue: scenario.testDescription))
        }
    }

    /// The regions the verdict actually puts load on. A capped session is still the
    /// planned session; a swap is the suggested one; active recovery and a rest day load
    /// nothing.
    private func recommendedRegions(_ assessment: ReadinessAssessment,
                                    planned: SessionKind?) -> Set<MuscleRegion> {
        switch assessment.verdict {
        case .activeRecovery:
            return []
        case .swapSession:
            return assessment.suggestedSession?.trainedRegions ?? []
        case .trainAsPlanned, .capIntensity:
            return planned?.trainedRegions ?? []
        }
    }
}
