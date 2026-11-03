import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("calendar arithmetic is integer-exact and locale-free")
struct CalendarMathTests {
    @Test("the spec's own anchor day is a Monday")
    func anchorWeekday() {
        // `docs/SPEC.md` §9.1 writes the example daily-log block as "2026-11-09 (Mon)",
        // and the seeded program plans weekday 1 as Upper A — so this one assertion ties
        // the weekday arithmetic to the program.
        #expect(Fix.monday.isoWeekday == 1)
        #expect(Fix.program.kind(forWeekday: Fix.monday.isoWeekday) == .upperA)
    }

    @Test("every weekday of the anchor week maps to its program day",
          arguments: zip(["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12",
                          "2026-11-13", "2026-11-14", "2026-11-15"],
                         [1, 2, 3, 4, 5, 6, 7]))
    func weekdaysAcrossAWeek(raw: String, weekday: Int) {
        #expect(Fix.date(raw).isoWeekday == weekday)
    }

    @Test("day differences cross months, years and a leap day")
    func dayDifferences() {
        #expect(Fix.date("2026-11-09").days(until: Fix.date("2026-11-09")) == 0)
        #expect(Fix.date("2026-11-30").days(until: Fix.date("2026-12-01")) == 1)
        #expect(Fix.date("2026-12-31").days(until: Fix.date("2027-01-01")) == 1)
        #expect(Fix.date("2026-11-09").days(until: Fix.date("2026-11-02")) == -7)
        // 2028 is a leap year, so February has 29 days.
        #expect(Fix.date("2028-02-28").days(until: Fix.date("2028-03-01")) == 2)
        #expect(Fix.date("2027-02-28").days(until: Fix.date("2027-03-01")) == 1)
    }

    @Test("adding days is the inverse of counting them", arguments: [-400, -31, -1, 0, 1, 31, 400])
    func addingRoundTrips(offset: Int) {
        let moved = Fix.monday.adding(days: offset)
        #expect(Fix.monday.days(until: moved) == offset)
        #expect(moved.adding(days: -offset) == Fix.monday)
    }

    @Test("a trailing window of 7 ends on its own day and starts six days earlier")
    func trailingWindow() {
        let window = Fix.monday.trailingWindow(days: 7)
        #expect(window.count == 7)
        #expect(window.first == Fix.date("2026-11-03"))
        #expect(window.last == Fix.monday)
        #expect(Fix.monday.trailingWindow(days: 0).isEmpty)
    }
}
