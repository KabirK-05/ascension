import AscensionCore
import Foundation

/// How Train writes a number.
///
/// Values and units are separated so that `ValueRow` can keep the unit inline and small
/// (`docs/DESIGN_RULES.md` §3.2), and deltas use the typographic minus the spec's own
/// examples use.
enum TrainFormat {
    static let minus = "\u{2212}"

    /// `48` → `("48", "min")`, `72` → `("1h12", nil)`. An hour is read as an hour.
    static func duration(minutes: Int) -> (value: String, unit: String?) {
        let clamped = max(0, minutes)
        guard clamped >= 60 else { return ("\(clamped)", "min") }
        return ("\(clamped / 60)h\(String(format: "%02d", clamped % 60))", nil)
    }

    /// `-3` → `"−3"`, `6` → `"+6"`. Zero keeps its sign off.
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\(minus)\(abs(value))" }
        return "0"
    }

    /// `22.5` → `"22.5"`, `20.0` → `"20"`. Never a precision the plates do not have.
    static func weight(_ kilograms: Double) -> String {
        let text = String(format: "%.1f", kilograms)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// `2026-11-03` → `"Mon 3 Nov"`. A date identifies; it does not measure.
    static func day(_ date: CalendarDate, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        guard let moment = calendar.date(from: DateComponents(
            year: date.year, month: date.month, day: date.day, hour: 12)) else {
            return date.rawValue
        }
        return formatter.string(from: moment)
    }

    /// The single letter under a day in the week strip.
    static func weekdayInitial(_ weekday: Int) -> String {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        guard (1...letters.count).contains(weekday) else { return "" }
        return letters[weekday - 1]
    }
}
