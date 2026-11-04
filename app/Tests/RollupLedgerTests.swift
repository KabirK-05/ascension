import AscensionCore
import AscensionEngines
import Foundation
import Testing

@testable import Ascension

/// The ledger is the one piece of genuinely new logic this ticket adds, and the piece the
/// rest of the shell trusts: if "changed" is wrong, either the Worker is pushed the same
/// day forever or it never hears about a day at all.
@Suite("the rollup ledger")
struct RollupLedgerTests {
    private let goals = Seed.goalSettings
    private let today = CalendarDate.literal("2026-11-03")

    private func rollup(_ date: CalendarDate, steps: Int? = nil,
                        at stamp: String = "2026-11-03T06:00:00-05:00") -> DayRollup {
        var day = DayRollup(date: date, timezone: Seed.timezone,
                            updatedAt: Timestamp.literal(stamp),
                            wins: Wins(session: false, protein: false,
                                       steps: false, sleep: false))
        day.activity.steps = steps
        return day
    }

    @Test("a day the ledger has not seen is queued for the Worker")
    func mergeQueuesNewDays() {
        var ledger = RollupLedger()
        ledger.merge([rollup(today, steps: 9_000)])

        #expect(ledger.pending.map(\.date) == [today])
        #expect(ledger.rollup(on: today)?.activity.steps == 9_000)
    }

    /// The reason `pendingDates` exists rather than a timestamp comparison. Every refresh
    /// re-stamps `updatedAt` from the clock, so comparing those would mark every day
    /// pending on every tab load and push the same rollups all day.
    @Test("re-reading the same day with a fresh timestamp does not queue it again")
    func timestampAloneIsNotAChange() {
        var ledger = RollupLedger()
        ledger.merge([rollup(today, steps: 9_000)])
        ledger.markPushed(ledger.pending)

        ledger.merge([rollup(today, steps: 9_000, at: "2026-11-03T21:30:00-05:00")])

        #expect(ledger.pending.isEmpty)
    }

    @Test("a measurement that actually changed queues the day again")
    func contentChangeQueuesTheDay() {
        var ledger = RollupLedger()
        ledger.merge([rollup(today, steps: 9_000)])
        ledger.markPushed(ledger.pending)

        ledger.merge([rollup(today, steps: 11_200)])

        #expect(ledger.pending.map(\.date) == [today])
        #expect(ledger.rollup(on: today)?.activity.steps == 11_200)
    }

    /// A partial push is a real outcome: the days that landed stop being pending and the
    /// rest stay queued, which is why `markPushed` takes the rollups rather than a count.
    @Test("only the days actually pushed stop being pending")
    func partialPushKeepsTheRest() {
        var ledger = RollupLedger()
        let first = rollup(today.adding(days: -1), steps: 4_000)
        let second = rollup(today, steps: 9_000)
        ledger.merge([first, second])

        ledger.markPushed([first])

        #expect(ledger.pending.map(\.date) == [today])
    }

    @Test("history is the trailing window, earliest first")
    func historyIsAWindow() {
        var ledger = RollupLedger()
        ledger.merge((0..<10).map { rollup(today.adding(days: -$0), steps: $0 * 100) })

        let window = ledger.history(endingOn: today, days: 3)

        #expect(window.map(\.date) == [today.adding(days: -2), today.adding(days: -1), today])
    }

    @Test("retention drops days beyond the window, and their pending marks with them")
    func pruneHonoursRetention() {
        var ledger = RollupLedger()
        let ancient = today.adding(days: -(RollupLedger.retentionDays + 5))
        ledger.merge([rollup(ancient), rollup(today)])

        ledger.prune(asOf: today)

        #expect(ledger.rollup(on: ancient) == nil)
        #expect(ledger.pending.map(\.date) == [today])
    }
}
