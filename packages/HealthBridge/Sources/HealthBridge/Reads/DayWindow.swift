import AscensionCore
import Foundation

/// Turns a contract calendar date into the instants HealthKit queries need.
///
/// The contract keys everything on a local `YYYY-MM-DD` in the user's timezone, and
/// HealthKit only speaks `Date`. This is the one place that conversion happens, so a
/// day boundary cannot drift between the reader, the mirrors and the export.
public struct DayWindow: Hashable, Sendable {
    public let date: CalendarDate
    public let timeZone: TimeZone
    public let interval: DateInterval

    public init?(date: CalendarDate, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        self.date = date
        self.timeZone = timeZone
        self.interval = DateInterval(start: start, end: end)
    }

    /// Where to look for last night's sleep: from noon the previous day to noon on this
    /// one, the window that holds exactly one night for any plausible bedtime.
    public var sleepLookback: DateInterval {
        let noonOffset: TimeInterval = 12 * 3600
        return DateInterval(start: interval.start.addingTimeInterval(-noonOffset),
                            end: interval.start.addingTimeInterval(noonOffset))
    }

    /// The calendar date an instant falls on in this window's timezone.
    public static func calendarDate(for instant: Date, timeZone: TimeZone) -> CalendarDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return CalendarDate(year: year, month: month, day: day)
    }
}
