import AscensionCore
import Foundation

// Calendar arithmetic for `CalendarDate`, done in integers.
//
// The engines may not read `Calendar.current` or any other ambient state (spec §8: pure
// functions over value types), so day counting goes through the Julian day number rather
// than through `Calendar`. Integer arithmetic over a proleptic Gregorian calendar is
// exactly what the contract's `YYYY-MM-DD` keys mean, and it is identical on every
// machine, in every locale, under every timezone database.

extension CalendarDate {
    /// Days since the Julian epoch. Monotonic across month and year boundaries, so the
    /// difference between two of these is a day count.
    public var julianDay: Int {
        let adjust = (14 - month) / 12
        let years = year + 4800 - adjust
        let months = month + 12 * adjust - 3
        return day + (153 * months + 2) / 5 + 365 * years
            + years / 4 - years / 100 + years / 400 - 32_045
    }

    /// `other - self` in days. Negative when `other` is earlier.
    public func days(until other: CalendarDate) -> Int {
        other.julianDay - julianDay
    }

    /// The ISO-8601 weekday, Monday = 1 through Sunday = 7, matching
    /// `ProgramDayEntry.weekday`.
    public var isoWeekday: Int {
        julianDay % 7 + 1
    }

    /// The date `days` later, or earlier when `days` is negative.
    public func adding(days: Int) -> CalendarDate {
        Self.from(julianDay: julianDay + days)
    }

    /// The inverse of ``julianDay``.
    static func from(julianDay: Int) -> CalendarDate {
        let era = julianDay + 32_044
        let quadricentennial = (4 * era + 3) / 146_097
        let dayOfCentury = era - 146_097 * quadricentennial / 4
        let centennial = (4 * dayOfCentury + 3) / 1461
        let dayOfYear = dayOfCentury - 1461 * centennial / 4
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex + 3 - 12 * (monthIndex / 10)
        let year = 100 * quadricentennial + centennial - 4800 + monthIndex / 10
        return CalendarDate(year: year, month: month, day: day)
            ?? CalendarDate.literal("1970-01-01")
    }

    /// The `count` days ending on this one, earliest first. A window of 7 ending on the
    /// 9th starts on the 3rd.
    public func trailingWindow(days count: Int) -> [CalendarDate] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { adding(days: -$0) }
    }
}
