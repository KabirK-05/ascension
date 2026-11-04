import AscensionCore
import Foundation

/// Number, date and duration rendering for the exported files.
///
/// Every helper here is locale-independent on purpose. `NumberFormatter` would render
/// `2,180` as `2.180` under a European locale and `−0.4` with a different minus sign,
/// and an export has to read the same on the user's Mac as it does in CI.
enum Format {
    /// The shortest exact form of a double: `73.6`, `24`, `-0.4`. Swift's own `Double`
    /// description is shortest-round-trip and locale-free, so an integral value only
    /// needs its `.0` trimmed.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    /// A double rounded to `places` decimals, with no trailing zeros beyond them.
    static func decimal(_ value: Double, places: Int) -> String {
        guard value.isFinite else { return "" }
        let scale = pow(10.0, Double(places))
        return number((value * scale).rounded() / scale)
    }

    /// A double at exactly `places` decimals: `74.0` → `74.0`.
    ///
    /// Weights use this rather than `decimal`, so a column of them lines up instead of
    /// alternating between `73.9` and `74`.
    static func fixed(_ value: Double, places: Int) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.\(places)f", value)
    }

    /// An integer with thousands separators: `10240` → `10,240`.
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }

    /// A double rounded to a whole number and grouped: `2180.0` → `2,180`.
    static func groupedWhole(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return grouped(Int(value.rounded()))
    }

    /// A rate with an explicit sign, using the typographic minus the spec's example
    /// shows: `-0.4` → `−0.4`, `0.4` → `+0.4`.
    static func signed(_ value: Double, places: Int) -> String {
        let magnitude = decimal(abs(value), places: places)
        if value > 0 { return "+" + magnitude }
        if value < 0 { return "\u{2212}" + magnitude }
        return magnitude
    }

    /// Minutes as the journal writes a duration: `462` → `7h42`.
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return String(format: "%dh%02d", hours, remainder)
    }

    /// The local clock time of an instant: `19:04`.
    static func clockTime(_ timestamp: Timestamp, in environment: ExportEnvironment) -> String? {
        guard let date = timestamp.date else { return nil }
        let parts = environment.calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The three-letter weekday of a calendar date: `2026-11-09` → `Mon`.
    static func weekday(_ date: CalendarDate, in environment: ExportEnvironment) -> String? {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = 12
        let calendar = environment.calendar
        guard let resolved = calendar.date(from: components),
              let weekday = calendar.dateComponents([.weekday], from: resolved).weekday,
              weekdayNames.indices.contains(weekday - 1) else { return nil }
        return weekdayNames[weekday - 1]
    }
}

extension ReadinessVerdict {
    /// The verdict as the journal says it: `trainAsPlanned` → `train as planned`.
    var journalText: String {
        switch self {
        case .trainAsPlanned: return "train as planned"
        case .capIntensity: return "cap intensity"
        case .swapSession: return "swap session"
        case .activeRecovery: return "active recovery"
        }
    }
}

extension MealKind {
    var journalText: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }
}

extension String {
    /// A HealthKit activity-type name as a short label: `traditionalStrengthTraining`
    /// → `Strength`. `type` is deliberately an open string in the contract, so an
    /// unmapped value falls back to a readable form of itself rather than being dropped.
    var workoutTypeLabel: String {
        switch self {
        case "traditionalStrengthTraining", "functionalStrengthTraining": return "Strength"
        case "highIntensityIntervalTraining": return "HIIT"
        case "walking": return "Walk"
        case "running": return "Run"
        case "cycling": return "Cycle"
        case "hiking": return "Hike"
        case "swimming": return "Swim"
        case "rowing": return "Row"
        case "coreTraining": return "Core"
        case "yoga": return "Yoga"
        case "stairClimbing", "stairs": return "Stairs"
        default: return humanisedCamelCase
        }
    }

    /// `elliptical` → `Elliptical`, `mixedCardio` → `Mixed cardio`.
    var humanisedCamelCase: String {
        var words: [String] = []
        var current = ""
        for character in self {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character).lowercased()
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        guard let first = words.first else { return self }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst())
            .joined(separator: " ")
    }
}
