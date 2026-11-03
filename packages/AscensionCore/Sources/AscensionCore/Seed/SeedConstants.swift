import Foundation

/// The seed data this single-user app ships with (spec §2, §3).
///
/// Seeds are *data*: value types the app copies into SwiftData on first launch and the
/// user then edits in Settings. Nothing here is behaviour, and nothing downstream may
/// branch on it.
public enum Seed {
    public static let timezone = "America/Toronto"

    /// The day the current block starts, and the stamp every seed document carries.
    public static let programStartDate = CalendarDate.literal("2026-11-03")

    public static let seededAt = Timestamp.literal("2026-11-03T00:00:00-05:00")
}
