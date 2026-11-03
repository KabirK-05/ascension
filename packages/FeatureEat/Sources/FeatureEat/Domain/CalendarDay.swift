import AscensionCore
import Foundation

extension CalendarDate {
    /// The local day an instant falls in.
    ///
    /// `CalendarDate` is deliberately not built from a `Date` in AscensionCore — the
    /// contract keys on a local date string to avoid timezone drift — so the
    /// conversion happens here, once, against an explicit calendar.
    public init?(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDate? {
        guard let start = date(in: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: start) else {
            return nil
        }
        return CalendarDate(moved, calendar: calendar)
    }

    /// Today, or — if a calendar ever hands back components this type refuses — the
    /// seeded program start, so a screen renders rather than disappearing.
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> CalendarDate {
        CalendarDate(now, calendar: calendar) ?? Seed.goalSettings.programStartDate
    }
}
