import Foundation

/// A calendar day in the user's timezone, serialised as `YYYY-MM-DD`.
///
/// The contract keys every day on a local date string (`docs/EXPORT_SCHEMA.md`), so the
/// model carries that string rather than a `Date`: a `Date` would reintroduce exactly the
/// timezone drift the contract exists to avoid.
public struct CalendarDate: RawRepresentable, Hashable, Sendable, Comparable {
    public let rawValue: String
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(rawValue: String) {
        guard let parsed = Self.parse(rawValue) else { return nil }
        self.rawValue = rawValue
        self.year = parsed.year
        self.month = parsed.month
        self.day = parsed.day
    }

    public init?(year: Int, month: Int, day: Int) {
        let padded = String(format: "%04d-%02d-%02d", year, month, day)
        self.init(rawValue: padded)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private struct Components {
        let year: Int
        let month: Int
        let day: Int
    }

    private static func parse(_ value: String) -> Components? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = digits(parts[0], count: 4),
              let month = digits(parts[1], count: 2),
              let day = digits(parts[2], count: 2),
              (1...12).contains(month),
              (1...daysIn(month: month, year: year)).contains(day) else { return nil }
        return Components(year: year, month: month, day: day)
    }

    private static func digits(_ text: Substring, count: Int) -> Int? {
        guard text.count == count, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeapYear(year) ? 29 : 28
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = CalendarDate(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected a YYYY-MM-DD calendar date, found \"\(raw)\"")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CalendarDate: CustomStringConvertible {
    public var description: String { rawValue }
}
