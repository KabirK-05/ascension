import Foundation

/// An instant serialised as ISO-8601 with an explicit UTC offset, e.g.
/// `2026-11-03T23:05:00-05:00`.
///
/// Validated structurally rather than by a date formatter so that the check is
/// deterministic and carries no shared mutable state.
public struct Timestamp: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Formats `date` in `timeZone`, which is how the app stamps everything it writes.
    public init(_ date: Date, timeZone: TimeZone) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        self.rawValue = formatter.string(from: date)
    }

    public var date: Date? {
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ]
        for options in optionSets {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let parsed = formatter.date(from: rawValue) { return parsed }
        }
        return nil
    }

    private static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, CalendarDate(rawValue: String(parts[0])) != nil else { return false }
        return isValidTimeOfDay(parts[1])
    }

    private static func isValidTimeOfDay(_ text: Substring) -> Bool {
        var body = text
        if body.hasSuffix("Z") {
            body = body.dropLast()
        } else {
            guard body.count > 6, isValidOffset(body.suffix(6)) else { return false }
            body = body.dropLast(6)
        }
        let clock = body.split(separator: ".", omittingEmptySubsequences: false)
        guard clock.count <= 2 else { return false }
        if clock.count == 2 {
            guard !clock[1].isEmpty,
                  clock[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        }
        let fields = clock[0].split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3,
              let hours = twoDigits(fields[0]), hours <= 23,
              let minutes = twoDigits(fields[1]), minutes <= 59,
              let seconds = twoDigits(fields[2]), seconds <= 60 else { return false }
        return true
    }

    private static func isValidOffset(_ text: Substring) -> Bool {
        let characters = Array(text)
        guard characters.count == 6,
              characters[0] == "+" || characters[0] == "-",
              characters[3] == ":",
              let hours = twoDigits(characters[1], characters[2]),
              let minutes = twoDigits(characters[4], characters[5]) else {
            return false
        }
        return hours <= 23 && minutes <= 59
    }

    private static func twoDigits(_ text: Substring) -> Int? {
        let characters = Array(text)
        guard characters.count == 2 else { return nil }
        return twoDigits(characters[0], characters[1])
    }

    private static func twoDigits(_ first: Character, _ second: Character) -> Int? {
        guard first.isASCII, second.isASCII,
              let high = first.wholeNumberValue, (0...9).contains(high),
              let low = second.wholeNumberValue, (0...9).contains(low) else { return nil }
        return high * 10 + low
    }
}

extension Timestamp: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Timestamp(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected an ISO-8601 timestamp with offset, found \"\(raw)\"")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Timestamp: CustomStringConvertible {
    public var description: String { rawValue }
}
