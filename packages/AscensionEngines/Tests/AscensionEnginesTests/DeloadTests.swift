import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("the deload prompt fires in the cadence week and keeps firing")
struct DeloadTests {
    static let start = Seed.programStartDate

    @Test("the seeded cadence is five weeks, which spec §F6 calls week 5–6")
    func cadenceIsSeeded() {
        #expect(Fix.goals.deloadEveryWeeks == 5)
        #expect(Self.start == Fix.date("2026-11-03"))
    }

    @Test("week 1 is the first seven days of the block",
          arguments: zip([0, 1, 6, 7, 13, 14, 27, 28, 34, 35],
                         [1, 1, 1, 2, 2, 3, 4, 5, 5, 6]))
    func weeksIntoBlock(dayOffset: Int, expected: Int) {
        let asOf = Self.start.adding(days: dayOffset)
        #expect(DeloadDetector.weeksIntoBlock(start: Self.start, asOf: asOf) == expected)
    }

    @Test("a date before the block starts is week zero")
    func beforeTheBlock() {
        #expect(DeloadDetector.weeksIntoBlock(start: Self.start,
                                              asOf: Self.start.adding(days: -1)) == 0)
    }

    @Test("the prompt boundary: week 4 is not due, week 5 is, week 6 is overdue",
          arguments: [(21, false), (27, false), (28, true), (34, true), (35, true), (60, true)])
    func promptBoundary(dayOffset: Int, shouldPrompt: Bool) {
        let status = DeloadDetector.status(program: Fix.program, goals: Fix.goals,
                                           asOf: Self.start.adding(days: dayOffset))
        #expect(status.shouldPrompt == shouldPrompt)
    }

    @Test("the cadence week is due and the week after it is overdue")
    func dueThenOverdue() {
        let due = DeloadDetector.status(program: Fix.program, goals: Fix.goals,
                                        asOf: Self.start.adding(days: 28))
        #expect(due == .due(weeksIntoBlock: 5))

        let overdue = DeloadDetector.status(program: Fix.program, goals: Fix.goals,
                                            asOf: Self.start.adding(days: 35))
        #expect(overdue == .overdue(weeksIntoBlock: 6))
    }

    @Test("the day before the cadence week is not yet due")
    func justBeforeDue() {
        let status = DeloadDetector.status(program: Fix.program, goals: Fix.goals,
                                           asOf: Self.start.adding(days: 27))
        #expect(status == .notDue(weeksIntoBlock: 4))
    }

    @Test("a deload already running is not prompted for again")
    func activeDeload() {
        var program = Fix.program
        program.deload = DeloadSettings(active: true, loadFactor: 0.6, volumeFactor: 0.5)
        let status = DeloadDetector.status(program: program, goals: Fix.goals,
                                           asOf: Self.start.adding(days: 60))
        #expect(status == .active)
        #expect(!status.shouldPrompt)
        #expect(status.weeksIntoBlock == nil)
    }

    @Test("a cadence configured anywhere in spec §3's four-to-six-week range works",
          arguments: [4, 5, 6])
    func configurableCadence(weeks: Int) {
        var goals = Fix.goals
        goals.deloadEveryWeeks = weeks
        let dueDay = (weeks - 1) * 7
        #expect(DeloadDetector.status(program: Fix.program, goals: goals,
                                      asOf: Self.start.adding(days: dueDay))
            == .due(weeksIntoBlock: weeks))
        #expect(DeloadDetector.status(program: Fix.program, goals: goals,
                                      asOf: Self.start.adding(days: dueDay - 1))
            == .notDue(weeksIntoBlock: weeks - 1))
    }

    @Test("a cadence of zero configures no deload at all")
    func noCadence() {
        var goals = Fix.goals
        goals.deloadEveryWeeks = 0
        let status = DeloadDetector.status(program: Fix.program, goals: goals,
                                           asOf: Self.start.adding(days: 365))
        #expect(!status.shouldPrompt)
    }
}
