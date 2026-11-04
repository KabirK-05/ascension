import AscensionCore
import Foundation
@testable import SystemSurfaces
import Testing

@Suite("streak")
struct StreakTests {

    private func day(_ raw: String, wins: Int) -> DayRollup {
        let stamp = Timestamp(rawValue: "\(raw)T12:00:00-05:00")
            ?? Timestamp(Date(), timeZone: .gmt)
        return DayRollup(date: CalendarDate.literal(raw),
                         timezone: "America/Toronto",
                         updatedAt: stamp,
                         wins: Wins(session: wins > 0, protein: wins > 1,
                                    steps: wins > 2, sleep: wins > 3))
    }

    @Test("consecutive qualifying days are counted back from today")
    func countsBackwards() {
        let history = [
            day("2026-11-01", wins: 4),
            day("2026-11-02", wins: 3),
            day("2026-11-03", wins: 4)
        ]
        #expect(StreakRule.length(history: history, asOf: CalendarDate.literal("2026-11-03")) == 3)
    }

    @Test("a day below the threshold ends the streak")
    func thresholdBreaks() {
        let history = [
            day("2026-11-01", wins: 4),
            day("2026-11-02", wins: 2),
            day("2026-11-03", wins: 4)
        ]
        #expect(StreakRule.length(history: history, asOf: CalendarDate.literal("2026-11-03")) == 1)
    }

    @Test("today not yet qualifying does not break the run behind it")
    func todayInProgress() {
        let history = [
            day("2026-11-01", wins: 4),
            day("2026-11-02", wins: 4),
            day("2026-11-03", wins: 0)
        ]
        #expect(StreakRule.length(history: history, asOf: CalendarDate.literal("2026-11-03")) == 2)
    }

    @Test("a missing day ends the streak, because an unmeasured day is not a kept one")
    func gapBreaks() {
        let history = [
            day("2026-11-01", wins: 4),
            day("2026-11-03", wins: 4)
        ]
        #expect(StreakRule.length(history: history, asOf: CalendarDate.literal("2026-11-03")) == 1)
    }

    @Test("no history is a streak of zero, not a crash")
    func emptyHistory() {
        #expect(StreakRule.length(history: [], asOf: CalendarDate.literal("2026-11-03")) == 0)
    }
}
