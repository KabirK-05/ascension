import AscensionCore
import Foundation

/// Runs an export: `export.json`, one CSV per entity, the appended `daily-log.md` and
/// the overwritten `summary-latest.md` (spec §9.1–9.2).
///
/// Every file goes through `AtomicFileWriter`, so a crash leaves each one either as it
/// was or fully replaced. The export as a whole is not a transaction — it does not need
/// to be: the JSON and CSVs are regenerated wholesale next run and the journal dedupes
/// by day, so re-running after a failure converges.
public struct ExportService: Sendable {
    public let destination: ExportDestination
    public let environment: ExportEnvironment
    public let writer: AtomicFileWriter

    public init(destination: ExportDestination,
                environment: ExportEnvironment = ExportEnvironment(),
                writer: AtomicFileWriter = AtomicFileWriter()) {
        self.destination = destination
        self.environment = environment
        self.writer = writer
    }

    /// The nightly background entry point. Register it against
    /// `NightlyExport.taskIdentifier`, which `Project.swift` already declares in
    /// `BGTaskSchedulerPermittedIdentifiers`.
    public func runNightly(_ snapshot: ExportSnapshot) throws -> ExportResult {
        try run(snapshot, trigger: .nightly)
    }

    /// The Settings button, and the `trigger_export` mutation.
    public func runOnDemand(_ snapshot: ExportSnapshot) throws -> ExportResult {
        try run(snapshot, trigger: .onDemand)
    }

    /// Resolves the user's folder and writes into it.
    public func run(_ snapshot: ExportSnapshot, trigger: ExportTrigger) throws -> ExportResult {
        let folder = try destination.resolve()
        defer { folder.release() }
        return try write(snapshot, to: folder.url, trigger: trigger,
                         bookmarkRefreshed: folder.wasStale)
    }

    /// Writes into an explicit folder, with no bookmark involved — the share-sheet path,
    /// and what the tests drive.
    public func write(_ snapshot: ExportSnapshot, to folder: URL,
                      trigger: ExportTrigger,
                      bookmarkRefreshed: Bool = false) throws -> ExportResult {
        let exportedAt = environment.exportedAt
        var fileNames: [String] = []

        let payload = ExportPayload(snapshot: snapshot, exportedAt: exportedAt)
        try writer.write(try payload.encoded(), to: folder.appendingPathComponent("export.json"))
        fileNames.append("export.json")

        for table in CSVTables.all(for: snapshot) {
            try writer.write(try table.encoded(),
                             to: folder.appendingPathComponent(table.fileName))
            fileNames.append(table.fileName)
        }

        let added = try appendJournal(snapshot, in: folder)
        if !added.isEmpty { fileNames.append(DailyLogAppender.fileName) }

        try writeSummary(snapshot, in: folder)
        fileNames.append(SummaryRenderer.fileName)

        return ExportResult(trigger: trigger, exportedAt: exportedAt, folder: folder,
                            fileNames: fileNames, recordCounts: payload.recordCounts,
                            journalDatesAdded: added, bookmarkRefreshed: bookmarkRefreshed)
    }

    private func appendJournal(_ snapshot: ExportSnapshot,
                               in folder: URL) throws -> [CalendarDate] {
        let url = folder.appendingPathComponent(DailyLogAppender.fileName)
        let existing = try writer.read(url).flatMap { String(data: $0, encoding: .utf8) }
        let renderer = DailyLogRenderer(environment: environment, snapshot: snapshot)
        let append = DailyLogAppender(renderer: renderer).append(snapshot.rollups, to: existing)
        guard let contents = append.contents else { return [] }
        try writer.write(Data(contents.utf8), to: url)
        return append.addedDates
    }

    private func writeSummary(_ snapshot: ExportSnapshot, in folder: URL) throws {
        let renderer = SummaryRenderer(environment: environment, snapshot: snapshot)
        try writer.write(Data(try renderer.render().utf8),
                         to: folder.appendingPathComponent(SummaryRenderer.fileName))
    }
}
