import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("the trends report assembles every §F6 number from one pass over history")
struct TrendsEngineTests {
    static let clock = Fix.clock("2026-12-07T20:00:00-05:00")

    /// Five weeks of a plausible block: four lifting days a week, weigh-ins trending
    /// down 0.08 kg a day, protein hit on most days.
    static let history: [DayRollup] = (0..<35).map { offset in
        let date = Fix.date("2026-12-07").adding(days: -offset)
        let planned = Fix.program.kind(forWeekday: date.isoWeekday) ?? .rest
        let isTraining = planned.isTrainingDay
        return Fix.rollup(date: date,
                          weightKg: 73.0 + 0.08 * Double(offset),
                          proteinG: offset % 5 == 0 ? 120 : 148,
                          asleepMinutes: 455,
                          consistencySd7Minutes: 31,
                          restingHrBpm: 57,
                          hrvSdnnMs: 41,
                          vo2Max: 44.0,
                          sessionPlanned: planned,
                          sessionDone: isTraining,
                          loadAu: isTraining ? 6_000 : nil,
                          workouts: isTraining ? [Fix.workout(on: date)] : [])
    }

    @Test("the report dates itself from the injected clock")
    func reportIsDatedByTheClock() {
        let report = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                         program: Fix.program, clock: Self.clock)
        #expect(report.asOf == Fix.date("2026-12-07"))
        #expect(report.weight.asOf == report.asOf)
        #expect(report.load.asOf == report.asOf)
        #expect(report.habits.asOf == report.asOf)
    }

    @Test("weight, load, habits and the deload prompt all come through")
    func reportIsComplete() {
        let report = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                         program: Fix.program, clock: Self.clock)
        #expect(report.weight.latestAverageKg != nil)
        #expect((report.weight.rateKgPerWeek ?? 0) < 0)
        #expect(report.weight.kgToGoal != nil)
        #expect(report.load.band == .optimal)
        #expect(!report.load.spikeAfterLayoff)
        // The habit window is 28 days by default, which is four weeks of four lifting
        // days — not the 35 days of history the fixture holds.
        #expect(report.habits.windowDays == 28)
        #expect(report.habits.plannedSessions == 16)
        #expect(report.habits.completedSessions == 16)
        #expect(report.habits.adherencePct == 100)
        #expect(report.habits.proteinHitRatePct > 70)
    }

    @Test("five weeks into the block, the deload prompt is up")
    func deloadPromptIsReached() {
        let report = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                         program: Fix.program, clock: Self.clock)
        // The block started 2026-11-03; 2026-12-07 is 34 days in, which is week 5.
        #expect(report.deload == .due(weeksIntoBlock: 5))
        #expect(report.deload.shouldPrompt)
    }

    @Test("a 0.56 kg/week loss sits between the thresholds and suggests nothing")
    func noSuggestionAtAHealthyRate() {
        let report = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                         program: Fix.program, clock: Self.clock)
        #expect(report.calorieSuggestion == nil)
    }

    @Test("an empty history produces a report of nils rather than zeroes")
    func emptyHistory() {
        let report = TrendsEngine.report(history: [], goals: Fix.goals,
                                         program: Fix.program, clock: Self.clock)
        #expect(report.weight.latestAverageKg == nil)
        #expect(report.weight.rateKgPerWeek == nil)
        #expect(report.weight.kgToGoal == nil)
        #expect(report.calorieSuggestion == nil)
        #expect(report.load.acuteChronicRatio == nil)
        #expect(report.load.band == nil)
        #expect(report.habits.adherencePct == nil)
    }

    @Test("the report is a pure function of its inputs")
    func deterministic() {
        let first = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                        program: Fix.program, clock: Self.clock)
        for _ in 0..<10 {
            let again = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                            program: Fix.program, clock: Self.clock)
            #expect(first == again)
        }
    }

    @Test("history order does not change the report")
    func orderIndependent() {
        let forwards = TrendsEngine.report(history: Self.history, goals: Fix.goals,
                                           program: Fix.program, clock: Self.clock)
        let backwards = TrendsEngine.report(history: Self.history.reversed(), goals: Fix.goals,
                                            program: Fix.program, clock: Self.clock)
        #expect(forwards == backwards)
    }

    @Test("the engines never mutate the documents they read")
    func documentsAreUntouched() {
        let goals = Fix.goals
        let program = Fix.program
        _ = TrendsEngine.report(history: Self.history, goals: goals, program: program,
                                clock: Self.clock)
        _ = ReadinessEngine.assess(ReadinessHistory.input(history: Self.history,
                                                          clock: Self.clock,
                                                          program: program, goals: goals))
        #expect(goals == Fix.goals)
        #expect(program == Fix.program)
    }
}

@Suite("the clock is the only source of now")
struct EngineClockTests {
    @Test("today is the local date of the injected instant")
    func todayFollowsTheInstant() {
        let clock = Fix.clock("2026-11-09T00:30:00-05:00")
        #expect(clock.today == Fix.monday)
        #expect(clock.timezone == "America/Toronto")
    }

    @Test("a late-evening instant still belongs to its own local day")
    func lateEveningStaysLocal() {
        // 23:30 in Toronto is already the next day in UTC. The contract keys days on the
        // local date, so this must still read as the 9th.
        #expect(Fix.clock("2026-11-09T23:30:00-05:00").today == Fix.monday)
    }

    @Test("hours between two instants are exact and signed")
    func hoursBetween() {
        let earlier = Fix.stamp("2026-11-07T07:00:00-05:00")
        let later = Fix.stamp("2026-11-09T07:00:00-05:00")
        #expect(EngineClock.hours(from: earlier, to: later) == 48)
        #expect(EngineClock.hours(from: later, to: earlier) == -48)
        #expect(Fix.clock().hoursSince(earlier) == 48)
    }

    @Test("hours across an offset change are read from the offsets, not guessed")
    func hoursAcrossOffsets() {
        // Toronto leaves daylight saving on 2026-11-01, so these two stamps carry
        // different offsets and are 24 h apart, not 25.
        let before = Fix.stamp("2026-10-31T12:00:00-04:00")
        let after = Fix.stamp("2026-11-01T12:00:00-05:00")
        #expect(EngineClock.hours(from: before, to: after) == 25)
    }

    @Test("an unreadable instant yields no hours rather than zero")
    func unreadableInstant() {
        // A leap second is structurally valid in the contract but not parseable as an
        // instant, which is exactly the case that must not silently become zero.
        let broken = Fix.stamp("2026-11-09T07:00:60-05:00")
        #expect(EngineClock.hours(from: broken, to: Fix.stamp(Fix.mondayMorning)) == nil)
    }
}
