import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("weight: daily points, the rolling average, the rate and the distance left")
struct WeightTrendTests {
    static let asOf = Fix.date("2026-12-07")

    @Test("daily points come through in order, and only the days that have one")
    func dailyPoints() {
        let history = [Fix.rollup(date: Fix.date("2026-12-05"), weightKg: 73.8),
                       Fix.rollup(date: Fix.date("2026-12-03"), weightKg: 74.0),
                       Fix.rollup(date: Fix.date("2026-12-04"))]
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect(trend.points.map(\.date.rawValue) == ["2026-12-03", "2026-12-05"])
        #expect(trend.points.map(\.value) == [74.0, 73.8])
    }

    @Test("the rolling average is the mean of the trailing seven days")
    func rollingAverage() {
        // Seven weigh-ins, 74.0 down to 73.4 in 0.1 steps. The mean is 73.7.
        let history = Fix.weighIns(startKg: 74.0, dailyChangeKg: -0.1, count: 7,
                                   endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        guard let latest = trend.latestAverageKg else {
            Issue.record("seven weigh-ins must produce an average")
            return
        }
        #expect(abs(latest - 73.7) < 0.0001)
    }

    @Test("the window does not reach past seven days")
    func windowIsBounded() {
        // Four days at 70 kg, then a seven-day gap, then four days at 80 kg. The latest
        // average must see only the 80s.
        let recent = Fix.weighIns(startKg: 80, dailyChangeKg: 0, count: 4, endingOn: Self.asOf)
        let old = Fix.weighIns(startKg: 70, dailyChangeKg: 0, count: 4,
                               endingOn: Self.asOf.adding(days: -10))
        let trend = WeightTrendEngine.trend(history: old + recent, goals: Fix.goals,
                                            asOf: Self.asOf)
        #expect(trend.latestAverageKg == 80)
    }

    @Test("an average needs enough samples behind it",
          arguments: [(3, false), (4, true), (5, true)])
    func minimumSamples(count: Int, expected: Bool) {
        let history = Fix.weighIns(startKg: 74, dailyChangeKg: -0.1, count: count,
                                   endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect((trend.latestAverageKg != nil) == expected)
        #expect(WeightTrendOptions.standard.minimumSamples == 4)
    }

    @Test("the rate of change is negative while losing and scaled to a week")
    func rate() {
        // Fourteen days falling 0.1 kg a day: 0.7 kg a week.
        let history = Fix.weighIns(startKg: 75.0, dailyChangeKg: -0.1, count: 14,
                                   endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        guard let rate = trend.rateKgPerWeek else {
            Issue.record("two weeks of weigh-ins must produce a rate")
            return
        }
        #expect(abs(rate + 0.7) < 0.0001)
    }

    @Test("the rate is positive while gaining")
    func gainingRate() {
        let history = Fix.weighIns(startKg: 70.0, dailyChangeKg: 0.05, count: 14,
                                   endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect((trend.rateKgPerWeek ?? 0) > 0)
    }

    @Test("a flat fortnight has a rate of zero, not a missing one")
    func flatRate() {
        let history = Fix.weighIns(startKg: 73.5, dailyChangeKg: 0, count: 14,
                                   endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect(trend.rateKgPerWeek == 0)
    }

    @Test("too short a history has no rate rather than a fabricated one")
    func noRateWithoutSpan() {
        let history = Fix.weighIns(startKg: 74, dailyChangeKg: -0.1, count: 5,
                                   endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect(trend.latestAverageKg != nil)
        #expect(trend.rateKgPerWeek == nil)
    }

    @Test("distance to goal is measured from the average, not the last weigh-in")
    func distanceToGoal() {
        // Six days at 74.0 and a one-day water spike to 76.0. The average is what counts.
        var history = Fix.weighIns(startKg: 74.0, dailyChangeKg: 0, count: 6,
                                   endingOn: Self.asOf.adding(days: -1))
        history.append(Fix.rollup(date: Self.asOf, weightKg: 76.0))
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)

        #expect(trend.goalWeightKg == 68.0)
        guard let average = trend.latestAverageKg, let toGoal = trend.kgToGoal else {
            Issue.record("a full week of weigh-ins must produce an average")
            return
        }
        #expect(average < 76.0)
        #expect(abs(toGoal - (average - 68.0)) < 0.0001)
    }

    @Test("past the goal, the distance left is negative")
    func pastTheGoal() {
        let history = Fix.weighIns(startKg: 67.0, dailyChangeKg: 0, count: 7, endingOn: Self.asOf)
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect((trend.kgToGoal ?? 0) < 0)
    }

    @Test("an empty history produces nothing rather than zeroes")
    func emptyHistory() {
        let trend = WeightTrendEngine.trend(history: [], goals: Fix.goals, asOf: Self.asOf)
        #expect(trend.points.isEmpty)
        #expect(trend.rollingAverage.isEmpty)
        #expect(trend.latestAverageKg == nil)
        #expect(trend.rateKgPerWeek == nil)
        #expect(trend.kgToGoal == nil)
    }

    @Test("days after the cut-off are ignored")
    func futureDaysIgnored() {
        var history = Fix.weighIns(startKg: 74, dailyChangeKg: 0, count: 7, endingOn: Self.asOf)
        history.append(Fix.rollup(date: Self.asOf.adding(days: 3), weightKg: 60))
        let trend = WeightTrendEngine.trend(history: history, goals: Fix.goals, asOf: Self.asOf)
        #expect(trend.latestAverageKg == 74)
    }
}
