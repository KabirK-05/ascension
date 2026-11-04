import AscensionCore
import Foundation

/// Why an export ran.
public enum ExportTrigger: String, Codable, Hashable, Sendable {
    /// The nightly background task (spec §9.2).
    case nightly
    /// The button in Settings, or a `trigger_export` mutation Muse appended.
    case onDemand
}

/// What an export actually wrote.
///
/// Returned rather than logged so the app can persist it as the `ExportManifest`
/// (`AscensionCore`) and show Settings the real numbers — `ExportKit` owns no store.
public struct ExportResult: Hashable, Sendable {
    public let trigger: ExportTrigger
    public let exportedAt: Timestamp
    public let folder: URL
    /// File names written this run, in write order.
    public let fileNames: [String]
    /// Rows per entity, the same counts `export.json` carries.
    public let recordCounts: [String: Int]
    /// Days appended to `daily-log.md`. Empty on a re-export of days already journalled.
    public let journalDatesAdded: [CalendarDate]
    /// True when the destination bookmark had gone stale and was refreshed.
    public let bookmarkRefreshed: Bool
}
