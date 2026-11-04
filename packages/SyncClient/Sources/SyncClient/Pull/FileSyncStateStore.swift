import Foundation

/// ``SyncState`` in a JSON file, written atomically.
///
/// Durability is the point: the cursor and the applied-id ledger have to survive being
/// killed between a HealthKit write and its ack, so the file is replaced rather than
/// rewritten in place — a truncated file would re-apply or skip Muse's writes.
///
/// Not the Keychain: none of this is secret, and a background task must be able to read it
/// while the device is locked.
public struct FileSyncStateStore: SyncStateStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/Ascension/sync-state.json`, created on first save.
    public static func applicationSupport(
        fileManager: FileManager = .default,
        directoryName: String = "Ascension"
    ) throws -> FileSyncStateStore {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        return FileSyncStateStore(url: directory.appending(path: "sync-state.json"))
    }

    public func load() throws -> SyncState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SyncState() }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return SyncState() }
        return try SyncCoding.decoder().decode(SyncState.self, from: data)
    }

    public func save(_ state: SyncState) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try SyncCoding.prettyEncoder().encode(state)
        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
