import AscensionCore
import Foundation
import SyncClient

/// Every write this device applied, newest first, in a file.
///
/// An actor for the same reason ``RollupStore`` is one: a foreground drain, a background
/// refresh and a silent push can all be applying mutations at once, and a lost update here
/// would drop a row the user needs to be able to undo.
///
/// Append-only in spirit — a row is never removed, only stamped `undoneAt` — and pruned
/// only by count, so the file cannot grow without bound on a device that is never
/// reinstalled.
actor ChangeLog {
    /// Rows kept. Six months of a handful of writes a day, which is far more than Settings
    /// ever shows and small enough to read and rewrite whole.
    static let limit = 500

    private let url: URL?
    private var rows: [RecordedChange]?

    init(url: URL?) {
        self.url = url
    }

    /// `Application Support/Ascension/changes.json`, beside the rollup ledger.
    static func applicationSupport(fileManager: FileManager = .default,
                                   directoryName: String = "Ascension") -> ChangeLog {
        guard let base = try? fileManager.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil, create: true) else {
            return ChangeLog(url: nil)
        }
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        return ChangeLog(url: directory.appending(path: "changes.json"))
    }

    /// Newest first, which is the order Settings draws and the order a person asks in.
    func all() -> [RecordedChange] {
        load().sorted { $0.at.rawValue > $1.at.rawValue }
    }

    func change(id: String) -> RecordedChange? {
        load().first { $0.id == id }
    }

    /// Records one write. Keyed on the mutation id, so a redelivered mutation updates its
    /// row rather than adding a second one.
    func record(_ change: RecordedChange) {
        var updated = load().filter { $0.id != change.id }
        updated.append(change)
        updated.sort { $0.at.rawValue < $1.at.rawValue }
        if updated.count > Self.limit {
            updated.removeFirst(updated.count - Self.limit)
        }
        persist(updated)
    }

    /// Stamps a row as undone. The row stays: what was undone, and when, is part of the
    /// trail rather than a gap in it.
    func markUndone(id: String, at instant: Timestamp) {
        var updated = load()
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].undoneAt = instant
        persist(updated)
    }

    private func load() -> [RecordedChange] {
        if let rows { return rows }
        let loaded = url
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? SyncCoding.decoder().decode([RecordedChange].self, from: $0) }
            ?? []
        rows = loaded
        return loaded
    }

    /// A write failure keeps the rows correct for this launch rather than failing a drain:
    /// losing the ledger costs the undo button, and losing the mutation would cost the
    /// write itself.
    private func persist(_ updated: [RecordedChange]) {
        rows = updated
        guard let url, let data = try? SyncCoding.prettyEncoder().encode(updated) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
