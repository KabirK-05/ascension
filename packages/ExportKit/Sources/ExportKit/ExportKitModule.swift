/// `export.json`, CSV per entity, append-only `daily-log.md` and the rolling
/// `summary-latest.md` (spec §9.1, `docs/EXPORT_SCHEMA.md` §4).
///
/// This module is the data-ownership guarantee: *if a feature can't be exported, don't
/// build it* (spec §3). It depends on `AscensionCore` and Foundation, and on nothing
/// else — no SwiftUI, no HealthKit, no networking — so it tests on macOS without a
/// simulator and the files it writes can be read by Claude Code, by the local MCP
/// server (ASC-17) or by hand.
public enum ExportKitModule {
    /// Schema contract version this module is written against.
    /// See `docs/EXPORT_SCHEMA.md`.
    public static let schemaVersion = 1
}
