import AscensionCore
import Foundation

/// The clock, injected.
///
/// Nothing in this package reads `Date()` from ambient state: a rollup's `updatedAt`, a
/// retry's backoff and the nightly schedule are all derived from here, so a test can pin
/// them and two runs of the same input produce the same bytes.
public protocol SyncClock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

extension SyncClock {
    /// `now` as the contract's ISO-8601-with-offset string, in this clock's timezone.
    public var timestamp: Timestamp {
        Timestamp(now, timeZone: timeZone)
    }
}

/// The clock the app runs on.
public struct SystemClock: SyncClock {
    public let timeZone: TimeZone

    /// `identifier` is the timezone from `goalSettings`, so the device and the contract
    /// agree on which day a sample belongs to.
    public init(timeZoneIdentifier: String = Seed.timezone) {
        self.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    public var now: Date { Date() }
}

/// A clock frozen at an instant, for tests and for one deterministic pass over a batch.
public struct FixedClock: SyncClock {
    public let now: Date
    public let timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }

    /// Fixes the clock at an instant written in the contract's own timestamp form.
    public init?(timestamp: Timestamp, timeZoneIdentifier: String = Seed.timezone) {
        guard let date = timestamp.date, let zone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }
        self.init(now: date, timeZone: zone)
    }
}
