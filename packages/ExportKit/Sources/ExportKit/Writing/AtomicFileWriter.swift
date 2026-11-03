import Foundation

/// Writes a file by writing a sibling temp file and then replacing the destination
/// with it.
///
/// A crash mid-export must never leave a truncated `export.json` or a half-appended
/// journal, and the folder is in iCloud Drive where a partial file would sync. The
/// replace step is a single file-system operation, so a reader sees either the previous
/// file whole or the new one whole, and never a prefix of either.
public struct AtomicFileWriter: Sendable {
    /// Runs after the temp file is written and before it replaces the destination.
    ///
    /// This is the seam the crash test uses: a hook that throws stands in for the
    /// process dying at the one moment where both files exist.
    public typealias CommitHook = @Sendable (URL) throws -> Void

    private let beforeCommit: CommitHook?

    public init(beforeCommit: CommitHook? = nil) {
        self.beforeCommit = beforeCommit
    }

    private var fileManager: FileManager { .default }

    public func write(_ data: Data, to url: URL) throws {
        let temporary = temporaryURL(for: url)
        try data.write(to: temporary, options: .atomic)
        defer { try? fileManager.removeItem(at: temporary) }

        try beforeCommit?(url)
        try commit(temporary, to: url)
    }

    /// The file's bytes, or `nil` when it does not exist yet — which is how an
    /// append-only file reads on its very first export.
    public func read(_ url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func temporaryURL(for url: URL) -> URL {
        // A sibling, so the replace stays inside one volume and cannot fall back to a
        // copy. Dot-prefixed so a sync client treats it as hidden scratch.
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    }

    private func commit(_ temporary: URL, to url: URL) throws {
        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
        } catch {
            throw ExportError.atomicReplaceFailed(file: url.lastPathComponent,
                                                  reason: String(describing: error))
        }
    }
}
