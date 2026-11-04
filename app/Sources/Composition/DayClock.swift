import AscensionCore
import AscensionEngines
import Foundation

/// Turning the contract's local dates into instants, in one place.
///
/// The app reasons in the user's timezone (`docs/EXPORT_SCHEMA.md`), so every conversion
/// between a `CalendarDate` and a `Date` has to carry that zone explicitly. Written here
/// rather than borrowed from a feature package: the shell depends on all four features, and
/// reaching into one of them for a date helper would make the shell's arithmetic depend on
/// which tab happens to own it.
struct DayClock: Sendable {
    let timeZone: TimeZone

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    /// From `goalSettings`, so a change to the user's timezone moves every day boundary.
    init(goals: GoalSettingsDocument) {
        self.timeZone = TimeZone(identifier: goals.timezone) ?? .gmt
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func startOfDay(_ date: CalendarDate) -> Date {
        let parts = DateComponents(timeZone: timeZone, year: date.year,
                                   month: date.month, day: date.day)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// Midday, which is what an entry with no recorded time of day is stamped with: it
    /// cannot drift into the previous or next local day however the zone shifts.
    func middayOf(_ date: CalendarDate) -> Date {
        startOfDay(date).addingTimeInterval(12 * 60 * 60)
    }

    /// The local day an instant falls on.
    func day(of instant: Date) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let date = CalendarDate(year: year, month: month, day: day) else {
            return CalendarDate.literal("1970-01-01")
        }
        return date
    }

    /// The instants spanned by whole local days from `first` through `last` inclusive.
    func interval(from first: CalendarDate, through last: CalendarDate) -> DateInterval {
        let start = startOfDay(first)
        let end = startOfDay(last.adding(days: 1))
        return DateInterval(start: start, end: max(start, end))
    }

    func engineClock(at instant: Date, goals: GoalSettingsDocument) -> EngineClock {
        EngineClock(now: Timestamp(instant, timeZone: timeZone), timezone: goals.timezone)
    }
}
