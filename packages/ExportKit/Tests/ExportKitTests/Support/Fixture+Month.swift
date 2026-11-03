import AscensionCore
import Foundation

@testable import ExportKit

// A realistic 28-day window, generated deterministically from the day index so the
// goldens are reproducible and no real health data is involved. The shape is the point:
// some days train and some rest, some measurements are missing, and one day is logged
// not at all — which is what makes the `null`-handling and adherence paths real.
extension Fixture {
    static let monthStart = CalendarDate.literal("2026-11-03")
    static let monthDays = 28

    /// 2026-11-03 → 2026-11-30, the 28 days ending on the export date.
    static var monthDates: [CalendarDate] {
        (0..<monthDays).compactMap { offset in
            let calendar = environment.calendar
            var components = DateComponents()
            components.year = monthStart.year
            components.month = monthStart.month
            components.day = monthStart.day + offset
            components.hour = 12
            guard let date = calendar.date(from: components) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day
            else { return nil }
            return CalendarDate(year: year, month: month, day: day)
        }
    }

    static var monthSnapshot: ExportSnapshot {
        let rollups = monthDates.enumerated().map { offset, date in
            monthRollup(date: date, offset: offset)
        }
        let meals = monthDates.enumerated().flatMap { offset, date in
            monthMeals(date: date, offset: offset)
        }
        return ExportSnapshot(rollups: rollups, documents: documents, meals: meals,
                              suggestions: [openSuggestion],
                              exerciseNames: exerciseNames)
    }

    static let openSuggestion = OpenSuggestion(
        id: "sug_01",
        createdAt: Timestamp.literal("2026-11-27T07:00:00-05:00"),
        kind: "calorieAdjustment",
        text: "Weight is falling 0.6 kg/week; drop the target by 100 kcal to 2,100 kcal.")

    /// Which session the program prescribes for a date, so planned-vs-done in the
    /// fixture follows the real seeded week rather than an invented one.
    static func plannedSession(on date: CalendarDate) -> SessionKind? {
        guard let weekday = isoWeekday(date) else { return nil }
        return Seed.program.kind(forWeekday: weekday)
    }

    static func isoWeekday(_ date: CalendarDate) -> Int? {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = 12
        let calendar = environment.calendar
        guard let resolved = calendar.date(from: components),
              let weekday = calendar.dateComponents([.weekday], from: resolved).weekday
        else { return nil }
        // Foundation counts Sunday as 1; the contract counts Monday as 1.
        return weekday == 1 ? 7 : weekday - 1
    }
}
