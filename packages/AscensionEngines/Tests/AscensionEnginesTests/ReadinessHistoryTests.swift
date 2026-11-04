import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("readiness inputs derived from history")
struct ReadinessHistoryTests {
    static let monday = Fix.monday
    static let clock = Fix.clock()

    @Test("baselines average the trailing 30 days and exclude today")
    func baselinesExcludeToday() {
        // Thirty days at HRV 40, then today at 10. A baseline that swallowed today would
        // drag itself toward the very reading it is meant to judge.
        var history = (1...30).map { offset in
            Fix.rollup(date: Self.monday.adding(days: -offset), hrvSdnnMs: 40)
        }
        history.append(Fix.rollup(date: Self.monday, hrvSdnnMs: 10))

        let baselines = ReadinessHistory.baselines(past: history, asOf: Self.monday)
        #expect(baselines.hrvSdnnMs == 40)
    }

    @Test("days outside the window do not move the baseline")
    func baselineWindowIsBounded() {
        let inside = (1...30).map { Fix.rollup(date: Self.monday.adding(days: -$0), hrvSdnnMs: 40) }
        let outside = (31...60).map { Fix.rollup(date: Self.monday.adding(days: -$0), hrvSdnnMs: 90) }
        let baselines = ReadinessHistory.baselines(past: inside + outside, asOf: Self.monday)
        #expect(baselines.hrvSdnnMs == 40)
    }

    @Test("a baseline with no samples is nil, not zero")
    func emptyBaselineIsNil() {
        let baselines = ReadinessHistory.baselines(past: [], asOf: Self.monday)
        #expect(baselines.hrvSdnnMs == nil)
        #expect(baselines.restingHrBpm == nil)
        #expect(baselines.trainingDayLoadAu == nil)
    }

    @Test("the load baseline averages training days only")
    func loadBaselineIgnoresRest() {
        let history = [
            Fix.rollup(date: Self.monday.adding(days: -1), loadAu: 0),
            Fix.rollup(date: Self.monday.adding(days: -2), loadAu: 6_000),
            Fix.rollup(date: Self.monday.adding(days: -3), loadAu: 4_000)
        ]
        let baselines = ReadinessHistory.baselines(past: history, asOf: Self.monday)
        #expect(baselines.trainingDayLoadAu == 5_000)
    }

    @Test("yesterday's load tells a rest day apart from an unmeasured one")
    func yesterdayLoadKeepsRestAndUnknownApart() {
        let yesterday = Self.monday.adding(days: -1)

        let measured = [Fix.rollup(date: yesterday, loadAu: 6_120)]
        #expect(ReadinessHistory.yesterdayLoadAu(past: measured, asOf: Self.monday) == 6_120)

        let rested = [Fix.rollup(date: yesterday)]
        #expect(ReadinessHistory.yesterdayLoadAu(past: rested, asOf: Self.monday) == 0)

        // A workout landed but its load could not be computed — missing heart rate.
        let unmeasured = [Fix.rollup(date: yesterday,
                                     workouts: [Fix.workout(on: yesterday, hrAvgBpm: nil)])]
        #expect(ReadinessHistory.yesterdayLoadAu(past: unmeasured, asOf: Self.monday) == nil)

        // Yesterday simply has not synced.
        #expect(ReadinessHistory.yesterdayLoadAu(past: [], asOf: Self.monday) == nil)
    }

    @Test("the last-trained stamp comes from the workout that actually ended last")
    func lastTrainedUsesWorkoutEnd() {
        let friday = Fix.date("2026-11-06")
        let history = [Fix.rollup(date: friday,
                                  sessionPlanned: .lowerB,
                                  sessionDone: true,
                                  workouts: [Fix.workout(on: friday, startHour: 18),
                                             Fix.workout(on: friday, startHour: 20)])]
        let stamps = ReadinessHistory.lastTrainedAt(history: history, asOf: Self.monday)
        #expect(stamps[.lowerBody] == Fix.stamp("2026-11-06T21:00:00-05:00"))
        #expect(stamps[.upperBody] == nil)
    }

    @Test("a session with no workout stamp falls back to the end of its own day")
    func lastTrainedFallsBackToEndOfDay() {
        // End of day, not start: a later stamp means fewer hours of recovery have
        // elapsed, which holds training back rather than waving it through.
        let friday = Fix.date("2026-11-06")
        let history = [Fix.rollup(date: friday, sessionPlanned: .upperB, sessionDone: true)]
        let stamps = ReadinessHistory.lastTrainedAt(history: history, asOf: Self.monday)
        #expect(stamps[.upperBody] == Fix.stamp("2026-11-06T23:59:00-05:00"))
    }

    @Test("a planned session that was not done does not count as training")
    func unfinishedSessionIsNotTraining() {
        let history = [Fix.rollup(date: Self.monday.adding(days: -1),
                                  sessionPlanned: .lowerA,
                                  sessionDone: false)]
        #expect(ReadinessHistory.lastTrainedAt(history: history, asOf: Self.monday).isEmpty)
    }

    @Test("the most recent session wins when a region was trained twice")
    func mostRecentSessionWins() {
        let history = [
            Fix.rollup(date: Fix.date("2026-11-02"), sessionPlanned: .upperA, sessionDone: true),
            Fix.rollup(date: Fix.date("2026-11-05"), sessionPlanned: .upperB, sessionDone: true)
        ]
        let stamps = ReadinessHistory.lastTrainedAt(history: history, asOf: Self.monday)
        #expect(stamps[.upperBody]?.rawValue.hasPrefix("2026-11-05") == true)
    }

    @Test("days after the clock are ignored")
    func futureDaysAreIgnored() {
        let history = [Fix.rollup(date: Self.monday.adding(days: 1),
                                  sessionPlanned: .upperA, sessionDone: true)]
        #expect(ReadinessHistory.lastTrainedAt(history: history, asOf: Self.monday).isEmpty)
    }

    @Test("a full-body session recovers both regions")
    func fullBodyStampsBothRegions() {
        let history = [Fix.rollup(date: Fix.date("2026-11-08"),
                                  sessionPlanned: .fullBody, sessionDone: true)]
        let stamps = ReadinessHistory.lastTrainedAt(history: history, asOf: Self.monday)
        #expect(stamps[.upperBody] != nil)
        #expect(stamps[.lowerBody] != nil)
    }

    @Test("the assembled input plans today from the program when the day has no plan")
    func plannedSessionFallsBackToTheProgram() {
        let input = ReadinessHistory.input(history: [], clock: Self.clock,
                                           program: Fix.program, goals: Fix.goals)
        #expect(input.plannedSession == .upperA)
        #expect(input.programSessions == Fix.sessions)
        #expect(input.targets == Fix.goals.targets)
    }

    @Test("the assembled input prefers the plan the day itself recorded")
    func recordedPlanWins() {
        let history = [Fix.rollup(date: Self.monday, sessionPlanned: .lowerB)]
        let input = ReadinessHistory.input(history: history, clock: Self.clock,
                                           program: Fix.program, goals: Fix.goals)
        #expect(input.plannedSession == .lowerB)
    }

    @Test("a realistic week assembles into a verdict that respects the program's spacing")
    func endToEnd() {
        // Upper B on Thursday and Lower B on Friday, both done; today is Monday, so both
        // regions have had the weekend and Upper A runs.
        var history = (1...30).map { offset in
            Fix.rollup(date: Self.monday.adding(days: -offset),
                       asleepMinutes: 460, restingHrBpm: 57, hrvSdnnMs: 41)
        }
        history.append(Fix.rollup(date: Fix.date("2026-11-05"), sessionPlanned: .upperB,
                                  sessionDone: true, loadAu: 6_000,
                                  workouts: [Fix.workout(on: Fix.date("2026-11-05"))]))
        history.append(Fix.rollup(date: Fix.date("2026-11-06"), sessionPlanned: .lowerB,
                                  sessionDone: true, loadAu: 6_200,
                                  workouts: [Fix.workout(on: Fix.date("2026-11-06"))]))
        history.append(Fix.rollup(date: Self.monday, asleepMinutes: 465,
                                  restingHrBpm: 56, hrvSdnnMs: 43,
                                  sessionPlanned: .upperA))

        let input = ReadinessHistory.input(history: history, clock: Self.clock,
                                           program: Fix.program, goals: Fix.goals)
        let assessment = ReadinessEngine.assess(input)
        #expect(input.plannedSession == .upperA)
        #expect(assessment.blockedRegions.isEmpty)
        #expect(assessment.verdict == .trainAsPlanned)
        #expect(assessment.reasons.count == 2)
    }

    @Test("yesterday's upper session blocks today's upper plan, end to end")
    func backToBackUpperIsBlocked() {
        let sunday = Self.monday.adding(days: -1)
        let history = [
            Fix.rollup(date: sunday, sessionPlanned: .upperB, sessionDone: true,
                       loadAu: 6_000, workouts: [Fix.workout(on: sunday)]),
            Fix.rollup(date: Self.monday, asleepMinutes: 465, restingHrBpm: 56,
                       hrvSdnnMs: 43, sessionPlanned: .upperA)
        ]
        let input = ReadinessHistory.input(history: history, clock: Self.clock,
                                           program: Fix.program, goals: Fix.goals)
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions[.upperBody] == .withinRecoveryWindow)
        #expect(assessment.verdict == .swapSession)
        #expect(assessment.suggestedSession?.trainedRegions == [.lowerBody])
    }
}
