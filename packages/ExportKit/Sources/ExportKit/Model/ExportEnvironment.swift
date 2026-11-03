import AscensionCore
import Foundation

/// The clock an export reads. Injected so a test can pin `exportedAt` and every
/// clock-time in the rendered files.
public protocol ExportClock: Sendable {
    var now: Date { get }
}

/// The real clock.
public struct SystemClock: ExportClock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock stopped at one instant.
public struct FixedClock: ExportClock {
    public let now: Date

    public init(_ now: Date) {
        self.now = now
    }

    /// A clock stopped at an ISO-8601 instant from the contract, e.g.
    /// `2026-11-30T06:00:00-05:00`.
    public init(_ timestamp: Timestamp) {
        self.now = timestamp.date ?? Date(timeIntervalSince1970: 0)
    }
}

/// Everything time-dependent, in one injectable place.
///
/// The app reasons in `America/Toronto` (`docs/EXPORT_SCHEMA.md`), and every date and
/// clock-time written into an export is rendered in `timeZone` — never in the device's
/// current zone, which would make a file read differently abroad.
public struct ExportEnvironment: Sendable {
    public var clock: any ExportClock
    public var timeZone: TimeZone

    public init(clock: any ExportClock = SystemClock(),
                timeZone: TimeZone = ExportEnvironment.defaultTimeZone) {
        self.clock = clock
        self.timeZone = timeZone
    }

    /// The project's timezone, resolved from the seed identifier.
    public static var defaultTimeZone: TimeZone {
        TimeZone(identifier: Seed.timezone) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
    }

    /// The environment an export runs in for a given settings document, so the user's
    /// own `timezone` wins over the seed default.
    public init(clock: any ExportClock = SystemClock(), goalSettings: GoalSettingsDocument) {
        self.clock = clock
        self.timeZone = TimeZone(identifier: goalSettings.timezone)
            ?? ExportEnvironment.defaultTimeZone
    }

    public var exportedAt: Timestamp {
        Timestamp(clock.now, timeZone: timeZone)
    }

    /// A Gregorian calendar fixed to `timeZone`, so weekday and clock-time rendering
    /// carry no ambient locale or zone.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
