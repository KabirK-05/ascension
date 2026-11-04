import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("protein hit-rate, adherence and the trend series")
struct HabitTrendsTests {
    static let asOf = Fix.date("2026-12-07")

    @Test("the protein floor is the contract's 140 g, tested at, below and above",
          arguments: [(139.0, 0), (140.0, 1), (141.0, 1)])
    func proteinFloorBoundary(proteinG: Double, hits: Int) {
        #expect(Fix.goals.targets.proteinMinG == 140)
        let history = [Fix.rollup(date: Self.asOf, proteinG: proteinG)]
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 1)
        #expect(trends.proteinHitDays == hits)
        #expect(trends.proteinHitRatePct == Double(hits) * 100)
    }

    @Test("the hit-rate denominator is every day in the window, logged or not")
    func unloggedDaysCountAsMisses() {
        // The same rule the contract gives the consistency grid: a win against a `null`
        // measurement is false, never true.
        let history = (0..<5).map { Fix.rollup(date: Self.asOf.adding(days: -$0), proteinG: 150) }
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 10)
        #expect(trends.proteinHitDays == 5)
        #expect(trends.proteinHitRatePct == 50)
    }

    @Test("a day logged without protein is a miss, not an abstention")
    func nullProteinIsAMiss() {
        let history = [Fix.rollup(date: Self.asOf)]
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 1)
        #expect(trends.proteinHitDays == 0)
    }

    @Test("adherence counts completed training days against planned ones")
    func adherence() {
        // Four lifting days planned, three done, three rest days.
        let plans: [(SessionKind, Bool)] = [(.upperA, true), (.lowerA, true), (.rest, false),
                                            (.upperB, true), (.lowerB, false), (.rest, false),
                                            (.rest, false)]
        let history = plans.enumerated().map { index, plan in
            Fix.rollup(date: Self.asOf.adding(days: -index),
                       sessionPlanned: plan.0, sessionDone: plan.1)
        }
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 7)
        #expect(trends.plannedSessions == 4)
        #expect(trends.completedSessions == 3)
        #expect(abs((trends.adherencePct ?? 0) - 75) < 0.0001)
    }

    @Test("a window that planned nothing has no adherence, rather than nought per cent")
    func noPlannedSessions() {
        let history = [Fix.rollup(date: Self.asOf, sessionPlanned: .rest)]
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 7)
        #expect(trends.plannedSessions == 0)
        #expect(trends.adherencePct == nil)
    }

    @Test("a rest day a workout landed on does not inflate adherence")
    func restDaysAreNotPlannedSessions() {
        let history = [Fix.rollup(date: Self.asOf, sessionPlanned: .rest, sessionDone: true)]
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 7)
        #expect(trends.plannedSessions == 0)
        #expect(trends.completedSessions == 0)
    }

    @Test("series carry only the days that hold a measurement")
    func seriesSkipGaps() {
        let history = [
            Fix.rollup(date: Self.asOf.adding(days: -2), restingHrBpm: 58, vo2Max: 44.2),
            Fix.rollup(date: Self.asOf.adding(days: -1)),
            Fix.rollup(date: Self.asOf, asleepMinutes: 455, consistencySd7Minutes: 32,
                       restingHrBpm: 57)
        ]
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 7)
        #expect(trends.restingHrSeries.map(\.value) == [58, 57] as [Double])
        #expect(trends.vo2MaxSeries.map(\.value) == [44.2] as [Double])
        #expect(trends.sleepMinutesSeries.map(\.value) == [455] as [Double])
        #expect(trends.sleepConsistencySeries.map(\.value) == [32] as [Double])
    }

    @Test("series come out in date order")
    func seriesAreOrdered() {
        let history = (0..<10).map {
            Fix.rollup(date: Self.asOf.adding(days: -$0), restingHrBpm: 50 + $0)
        }
        let trends = HabitTrendsEngine.trends(history: history, goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 28)
        let dates = trends.restingHrSeries.map(\.date)
        #expect(dates == dates.sorted())
        #expect(trends.restingHrSeries.last?.value == 50)
    }

    @Test("days outside the window are ignored")
    func windowIsBounded() {
        let inside = Fix.rollup(date: Self.asOf, proteinG: 150)
        let outside = Fix.rollup(date: Self.asOf.adding(days: -40), proteinG: 150)
        let trends = HabitTrendsEngine.trends(history: [inside, outside], goals: Fix.goals,
                                              asOf: Self.asOf, windowDays: 7)
        #expect(trends.proteinHitDays == 1)
    }

    @Test("an empty window reports zero hits rather than failing")
    func emptyWindow() {
        let trends = HabitTrendsEngine.trends(history: [], goals: Fix.goals, asOf: Self.asOf)
        #expect(trends.proteinHitDays == 0)
        #expect(trends.proteinHitRatePct == 0)
        #expect(trends.adherencePct == nil)
        #expect(trends.vo2MaxSeries.isEmpty)
    }
}
