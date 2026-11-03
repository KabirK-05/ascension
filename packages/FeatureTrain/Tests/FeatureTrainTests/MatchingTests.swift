import AscensionCore
import Foundation
import Testing

@testable import FeatureTrain

@Suite("planned versus done")
struct MatchingTests {
    private let week = Fixture.week()
    private let sunday = Fixture.date("2026-11-08")

    private func outcome(_ days: [TrainingDay], _ raw: String) -> DayOutcome? {
        days.first { $0.date.rawValue == raw }?.outcome
    }

    @Test("the seeded week is Upper A, Lower A, rest, Upper B, Lower B, rest, rest")
    func weekFollowsTheProgram() {
        let days = Fixture.match(week, today: sunday)
        #expect(days.map(\.planned) == [.upperA, .lowerA, .rest, .upperB, .lowerB, .rest, .rest])
    }

    @Test("a strength workout on a lifting day completes it")
    func strengthCompletesALiftingDay() {
        let monday = Fixture.date("2026-11-02")
        let days = Fixture.match(week, today: sunday,
                                 sessions: [Fixture.session("a", on: monday, hour: 18)])
        #expect(outcome(days, "2026-11-02") == .completed)
        #expect(days.first?.completedBy?.id == "a")
    }

    @Test("a walk on a lifting day is the finisher, not the session")
    func wrongTypeDoesNotComplete() throws {
        let monday = Fixture.date("2026-11-02")
        let walk = Fixture.session("walk", type: "walking", on: monday, hour: 18, minutes: 15)
        let days = Fixture.match(week, today: sunday, sessions: [walk])
        let day = try #require(days.first)
        #expect(day.outcome == .missed)
        #expect(day.completedBy == nil)
        // The walk is not discarded — it happened, and the day's debrief still holds it.
        #expect(day.extras.map(\.id) == ["walk"])
    }

    @Test("two workouts in one day credit one session, never two")
    func twoWorkoutsDoNotDoubleCount() throws {
        let monday = Fixture.date("2026-11-02")
        let first = Fixture.session("early", on: monday, hour: 7, minutes: 32)
        let second = Fixture.session("evening", on: monday, hour: 18, minutes: 54)
        let days = Fixture.match(week, today: sunday, sessions: [first, second])
        let day = try #require(days.first)
        #expect(day.outcome == .completed)
        // The longer one is the session; the short one is an extra, not a second credit.
        #expect(day.completedBy?.id == "evening")
        #expect(day.extras.map(\.id) == ["early"])
        #expect(Adherence.week(days).completed == 1)
    }

    @Test("a calendar block decides which of two eligible workouts was the session")
    func calendarBlockBreaksTheTie() throws {
        let monday = Fixture.date("2026-11-02")
        let longer = Fixture.session("morning", on: monday, hour: 7, minutes: 70)
        let planned = Fixture.session("planned", on: monday, hour: 18, minutes: 45)
        let days = Fixture.match(week, today: sunday, sessions: [longer, planned],
                                 blocks: [Fixture.block("b", on: monday, hour: 18)])
        #expect(try #require(days.first).completedBy?.id == "planned")
    }

    @Test("a rest day is never completed and never missed, whatever was recorded")
    func restDaysAreNeitherKeptNorBroken() throws {
        let wednesday = Fixture.date("2026-11-04")
        let days = Fixture.match(week, today: sunday,
                                 sessions: [Fixture.session("extra", on: wednesday, hour: 12)])
        let day = try #require(days.first { $0.date == wednesday })
        #expect(day.outcome == .rest)
        #expect(day.completedBy == nil)
        #expect(day.extras.map(\.id) == ["extra"])
        #expect(Adherence.week(days).planned == 4)
    }

    @Test("a planned day still ahead is upcoming; one gone by with nothing is missed")
    func elapsedDaysAreJudgedAndFutureDaysAreNot() {
        let days = Fixture.match(week, today: Fixture.date("2026-11-04"))
        #expect(outcome(days, "2026-11-02") == .missed)
        #expect(outcome(days, "2026-11-05") == .upcoming)
        // Today itself is still open: the session can still happen.
        #expect(outcome(days, "2026-11-04") == .rest)
    }

    @Test("today with nothing recorded yet is upcoming, not missed")
    func todayIsNotYetMissed() {
        let days = Fixture.match(week, today: Fixture.date("2026-11-05"))
        #expect(outcome(days, "2026-11-05") == .upcoming)
    }

    @Test("a late-evening workout belongs to the local day it started on")
    func lateWorkoutsStayOnTheirOwnDay() throws {
        let monday = Fixture.date("2026-11-02")
        let late = Fixture.session("late", on: monday, hour: 23, minutes: 50)
        let days = Fixture.match(week, today: sunday, sessions: [late])
        #expect(try #require(days.first).completedBy?.id == "late")
        #expect(outcome(days, "2026-11-03") == .missed)
    }

    @Test("a Zone 2 day is completed by cardio and not by lifting")
    func conditioningDaysWantCardio() throws {
        let program = Seed.historicalProgram
        let wednesday = Fixture.date("2026-11-04")
        let lift = Fixture.session("lift", on: wednesday, hour: 18)
        let walk = Fixture.session("walk", type: "walking", on: wednesday, hour: 19, minutes: 40)
        let liftedOnly = SessionMatcher.days([wednesday], program: program, today: Fixture.date("2026-11-08"),
                                             sessions: [lift], timeZone: Fixture.timeZone)
        #expect(try #require(liftedOnly.first).outcome == .missed)
        let walked = SessionMatcher.days([wednesday], program: program, today: Fixture.date("2026-11-08"),
                                         sessions: [lift, walk], timeZone: Fixture.timeZone)
        #expect(try #require(walked.first).completedBy?.id == "walk")
    }
}
