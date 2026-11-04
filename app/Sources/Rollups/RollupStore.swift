import AscensionCore
import Foundation
import SyncClient

/// ``RollupLedger`` in a JSON file, written atomically.
///
/// An actor because three callers reach it at once — a tab refresh, the nightly
/// `BGProcessingTask` and a silent-push drain — and a lost-update here would re-push days
/// the Worker already has or drop days it never got.
///
/// Not the Keychain and not SwiftData: none of this is secret, a background wake has to
/// read it while the device is locked, and it is a projection rather than a model — adding
/// it to `AscensionSchema` would mean a migration in `AscensionCore`, which is another
/// ticket's package.
actor RollupStore {
    private let url: URL
    private var ledger: RollupLedger?

    init(url: URL) {
        self.url = url
    }

    /// `Application Support/Ascension/rollups.json`, created on first save — the same
    /// directory `SyncClient`'s `FileSyncStateStore` uses.
    static func applicationSupport(fileManager: FileManager = .default,
                                   directoryName: String = "Ascension") throws -> RollupStore {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        return RollupStore(url: directory.appending(path: "rollups.json"))
    }

    /// The ledger, read from disk once per process.
    ///
    /// An unreadable or corrupt file is treated as an empty ledger rather than as a
    /// failure: the days are all re-derivable from HealthKit and the store, and refusing to
    /// launch over a bad cache would be the wrong trade.
    func load() -> RollupLedger {
        if let ledger { return ledger }
        let loaded = (try? Data(contentsOf: url))
            .flatMap { try? SyncCoding.decoder().decode(RollupLedger.self, from: $0) }
            ?? RollupLedger()
        ledger = loaded
        return loaded
    }

    /// Merges `incoming`, prunes to the retention window and persists.
    ///
    /// Returns the days now queued for the Worker, so a caller that has just refreshed can
    /// push without a second read.
    @discardableResult
    func merge(_ incoming: [DayRollup], asOf: CalendarDate) -> [DayRollup] {
        var updated = load()
        updated.merge(incoming)
        updated.prune(asOf: asOf)
        persist(updated)
        return updated.pending
    }

    func markPushed(_ pushed: [DayRollup]) {
        var updated = load()
        updated.markPushed(pushed)
        persist(updated)
    }

    /// A write failure is survivable — the ledger stays correct in memory for this launch
    /// and the days are re-derivable — so it is not propagated into a tab load.
    private func persist(_ updated: RollupLedger) {
        ledger = updated
        guard let data = try? SyncCoding.prettyEncoder().encode(updated) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        guard (try? data.write(to: temporary, options: .atomic)) != nil else { return }
        if (try? FileManager.default.replaceItemAt(url, withItemAt: temporary)) == nil {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}
