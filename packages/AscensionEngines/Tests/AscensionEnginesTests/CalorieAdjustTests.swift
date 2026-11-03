import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

/// The weekly calorie auto-adjust (spec §F6). Suggest-only: these tests pin both the
/// thresholds and the fact that nothing is ever written.
@Suite("the calorie rule suggests, on its documented thresholds")
struct CalorieAdjustTests {
    static let asOf = Fix.date("2026-12-07")

    @Test("the thresholds and targets are the spec's numbers")
    func constantsArePinned() {
        #expect(CalorieAdjustEngine.slowLossKgPerWeek == 0.3)
        #expect(CalorieAdjustEngine.fastLossKgPerWeek == 0.8)
        #expect(CalorieAdjustEngine.slowLossKcal == 2_000)
        #expect(CalorieAdjustEngine.fastLossKcal == 2_400)
        #expect(CalorieAdjustEngine.consecutiveSlowWeeks == 2)
        #expect(Fix.goals.targets.kcal == 2_200)
    }

    // MARK: - The slow branch: two weeks under 0.3 kg/week

    @Test("two weeks of slow loss suggests cutting to 2,000 kcal")
    func slowLossSuggestsCut() {
        let suggestion = suggest([0.2, 0.1])
        #expect(suggestion?.suggestedKcal == 2_000)
        #expect(suggestion?.currentKcal == 2_200)
    }

    @Test("the slow threshold is strict: at, just below, just above",
          arguments: [(0.29, 2_000 as Int?), (0.3, nil), (0.31, nil)])
    func slowThresholdBoundary(rate: Double, expected: Int?) {
        #expect(suggest([rate, rate])?.suggestedKcal == expected)
    }

    @Test("one slow week is not two")
    func oneSlowWeekIsNotEnough() {
        #expect(suggest([0.1, 0.5]) == nil)
        #expect(suggest([0.5, 0.1]) == nil)
    }

    @Test("a gaining fortnight counts as slow loss")
    func gainingIsSlowerThanSlow() {
        // Negative loss is gain, which is further from 0.3 than any slow week.
        #expect(suggest([-0.2, -0.1])?.suggestedKcal == 2_000)
    }

    @Test("a week with no rate behind it blocks the two-week test")
    func missingWeekBlocksSlowBranch() {
        #expect(suggest([0.1, nil]) == nil)
        #expect(suggest([nil, 0.1]) == nil)
        #expect(suggest([nil, nil]) == nil)
    }

    // MARK: - The fast branch: over 0.8 kg/week

    @Test("fast loss suggests raising to 2,400 kcal")
    func fastLossSuggestsRaise() {
        #expect(suggest([1.1, 0.9])?.suggestedKcal == 2_400)
    }

    @Test("the fast threshold is strict: at, just below, just above",
          arguments: [(0.79, nil as Int?), (0.8, nil), (0.81, 2_400)])
    func fastThresholdBoundary(rate: Double, expected: Int?) {
        #expect(suggest([rate, 0.5])?.suggestedKcal == expected)
    }

    @Test("fast loss acts on the latest week alone")
    func fastLossNeedsNoPersistence() {
        // The spec attaches a two-week test to the slow branch only, and waiting a second
        // week before suggesting *more* food is the reading that keeps the deficit
        // running. The resolved ambiguity is pinned here.
        #expect(suggest([1.2, 0.1])?.suggestedKcal == 2_400)
        // Last week was fast, this week is not: no suggestion.
        #expect(suggest([0.4, 1.2]) == nil)
    }

    @Test("the fast branch is checked before the slow one")
    func fastBranchWinsFirst() {
        #expect(suggest([0.9, 0.2])?.suggestedKcal == 2_400)
    }

    // MARK: - Shape

    @Test("no suggestion is made when the rule would propose the current target")
    func neverSuggestsANoOp() {
        var goals = Fix.goals
        goals.targets.kcal = 2_000
        let weeks = Self.weeks([0.1, 0.1])
        #expect(CalorieAdjustEngine.suggestion(weeklyLoss: weeks,
                                               currentKcal: goals.targets.kcal,
                                               asOf: Self.asOf) == nil)
    }

    @Test("a suggested target is one the contract would accept")
    func suggestionsPassContractValidation() {
        for weeks in [[0.1, 0.1], [1.2, 0.3]] {
            guard let kcal = suggest(weeks)?.suggestedKcal else {
                Issue.record("expected a suggestion for \(weeks)")
                continue
            }
            var goals = Fix.goals
            goals.targets.kcal = kcal
            #expect(throws: Never.self) { try goals.validate() }
        }
    }

    @Test("the identity is derived, so the same week always proposes the same suggestion")
    func identityIsDeterministic() {
        let first = suggest([0.1, 0.1])
        let second = suggest([0.1, 0.1])
        #expect(first?.id == second?.id)
        #expect(first?.id == "calorie-2026-12-07-2000")
        #expect(suggest([1.2, 0.2])?.id == "calorie-2026-12-07-2400")
    }

    @Test("the reason is a fact with units")
    func reasonIsAFact() {
        #expect(suggest([1.05, 0.2])?.reason == "losing 1.05 kg/week")
        #expect(suggest([0.12, 0.1])?.reason == "losing 0.12 and 0.1 kg/week over 2 weeks")
        // One week slow and one week healthy fires nothing, so there is no reason to give.
        #expect(suggest([0.12, 0.5])?.reason == nil)
    }

    @Test("the suggestion carries the weeks it read")
    func suggestionShowsItsWorking() {
        let suggestion = suggest([0.1, 0.2])
        #expect(suggestion?.weeklyLoss.count == 2)
        #expect(suggestion?.weeklyLoss.first?.weekEnding == Self.asOf)
        #expect(suggestion?.weeklyLoss.last?.weekEnding == Self.asOf.adding(days: -7))
    }

    @Test("the engine never mutates the targets it was handed")
    func goalsAreUntouched() {
        // Suggest-only (spec §F6: "never change targets silently"). The document the
        // engine read must come out of it identical.
        let before = Fix.goals
        let history = Fix.weighIns(startKg: 74.0, dailyChangeKg: -0.2, count: 21,
                                   endingOn: Self.asOf)
        _ = CalorieAdjustEngine.suggestion(history: history, goals: before, asOf: Self.asOf)
        #expect(before == Fix.goals)
    }

    // MARK: - Derived from real weigh-ins

    @Test("a real run of fast weight loss raises the suggestion")
    func derivedFastLoss() {
        // 0.15 kg a day is 1.05 kg a week.
        let history = Fix.weighIns(startKg: 78.0, dailyChangeKg: -0.15, count: 21,
                                   endingOn: Self.asOf)
        let suggestion = CalorieAdjustEngine.suggestion(history: history, goals: Fix.goals,
                                                        asOf: Self.asOf)
        #expect(suggestion?.suggestedKcal == 2_400)
    }

    @Test("a real run of stalled weight cuts the suggestion")
    func derivedSlowLoss() {
        let history = Fix.weighIns(startKg: 74.0, dailyChangeKg: -0.01, count: 21,
                                   endingOn: Self.asOf)
        let suggestion = CalorieAdjustEngine.suggestion(history: history, goals: Fix.goals,
                                                        asOf: Self.asOf)
        #expect(suggestion?.suggestedKcal == 2_000)
    }

    @Test("a healthy rate of loss suggests nothing")
    func derivedHealthyLoss() {
        // 0.075 kg a day is 0.525 kg a week — between the two thresholds.
        let history = Fix.weighIns(startKg: 76.0, dailyChangeKg: -0.075, count: 21,
                                   endingOn: Self.asOf)
        #expect(CalorieAdjustEngine.suggestion(history: history, goals: Fix.goals,
                                               asOf: Self.asOf) == nil)
    }

    @Test("no weigh-ins means no suggestion")
    func noDataNoSuggestion() {
        #expect(CalorieAdjustEngine.suggestion(history: [], goals: Fix.goals,
                                               asOf: Self.asOf) == nil)
    }

    private static func weeks(_ rates: [Double?]) -> [WeeklyLoss] {
        rates.enumerated().map { index, rate in
            WeeklyLoss(weekEnding: asOf.adding(days: -index * 7), lossKgPerWeek: rate)
        }
    }

    private func suggest(_ rates: [Double?]) -> CalorieSuggestion? {
        CalorieAdjustEngine.suggestion(weeklyLoss: Self.weeks(rates),
                                       currentKcal: Fix.goals.targets.kcal,
                                       asOf: Self.asOf)
    }
}
