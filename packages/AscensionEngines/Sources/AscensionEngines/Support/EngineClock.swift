import AscensionCore
import Foundation

/// The only way an engine learns what "now" is.
///
/// Nothing in this module reads `Date()` or `Calendar.current`: every entry point takes a
/// clock, so the same inputs always produce the same output and every rule is testable at
/// its boundary. The timezone travels with the instant because the contract keys days on
/// the user's local date (`docs/EXPORT_SCHEMA.md`).
public struct EngineClock: Hashable, Sendable {
    /// The instant the assessment is made, stamped in the user's offset.
    public let now: Timestamp

    /// The user's timezone identifier, e.g. `America/Toronto`.
    public let timezone: String

    /// The local calendar day `now` falls on.
    public let today: CalendarDate

    public init(now: Timestamp, timezone: String) {
        self.now = now
        self.timezone = timezone
        // `Timestamp` validates that everything before the `T` is a calendar date, so the
        // parse below cannot fail. The fallback exists only so this type needs no force
        // unwrapping, which the engines lint as an error.
        self.today = CalendarDate(rawValue: String(now.rawValue.prefix(10)))
            ?? CalendarDate.literal("1970-01-01")
    }

    /// Hours from `earlier` to ``now``, or `nil` when either instant cannot be read.
    ///
    /// `nil` is *unknown*, never zero — treating an unreadable timestamp as "trained just
    /// now" would block training, and treating it as zero hours would unblock it. Callers
    /// decide, and the readiness engine takes the cautious branch.
    public func hoursSince(_ earlier: Timestamp) -> Double? {
        Self.hours(from: earlier, to: now)
    }

    /// Hours between two instants. Negative when `later` precedes `earlier`.
    public static func hours(from earlier: Timestamp, to later: Timestamp) -> Double? {
        guard let start = earlier.date, let end = later.date else { return nil }
        return end.timeIntervalSince(start) / 3600
    }
}
