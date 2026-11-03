import Foundation

// Seed data is written as string literals, and the project lints force unwrapping as an
// error. These factories trap on a malformed literal instead, so a typo in a seed is a
// test failure with the offending string named rather than a bare crash.

extension CalendarDate {
    /// A date from a literal that is well-formed at authoring time.
    public static func literal(_ raw: String) -> CalendarDate {
        guard let value = CalendarDate(rawValue: raw) else {
            preconditionFailure("Malformed CalendarDate literal: \"\(raw)\"")
        }
        return value
    }
}

extension Timestamp {
    /// A timestamp from a literal that is well-formed at authoring time.
    public static func literal(_ raw: String) -> Timestamp {
        guard let value = Timestamp(rawValue: raw) else {
            preconditionFailure("Malformed Timestamp literal: \"\(raw)\"")
        }
        return value
    }
}
