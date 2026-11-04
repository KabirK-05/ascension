import Foundation

/// A folder the export is allowed to write to, held across launches.
///
/// The user picks an iCloud Drive folder once (spec §9.2). What persists is a
/// security-scoped bookmark, not a path: a sandboxed app has no standing permission to
/// a path, and iCloud moves its container between OS versions. Resolving the bookmark
/// both finds the folder again and re-grants the access.
public struct ExportDestination: Sendable {
    private let store: any BookmarkStore

    public init(store: any BookmarkStore) {
        self.store = store
    }

    public var hasDestination: Bool { store.loadBookmark() != nil }

    /// Records the folder the user just chose. The caller is inside the document
    /// picker's own access scope at this point, which is what makes the bookmark
    /// creatable.
    public func adopt(_ folder: URL) throws {
        try store.saveBookmark(try Self.bookmarkData(for: folder))
    }

    public func forget() { store.clearBookmark() }

    /// Resolves the stored bookmark, refreshing it when the system reports it stale.
    ///
    /// A stale bookmark still resolves — it just will not resolve again later — so the
    /// fix is to re-create it from the URL it just produced and store that. Skipping
    /// this is how a nightly export silently stops working a few OS updates in.
    public func resolve() throws -> ResolvedFolder {
        guard let bookmark = store.loadBookmark() else {
            throw ExportError.noDestinationChosen
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark,
                          options: Self.resolutionOptions,
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        } catch {
            throw ExportError.destinationUnresolvable(String(describing: error))
        }

        let accessing = url.startAccessingSecurityScopedResource()
        if isStale, let refreshed = try? Self.bookmarkData(for: url) {
            try? store.saveBookmark(refreshed)
        }

        do {
            try verifyDirectory(url)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        return ResolvedFolder(url: url, isAccessing: accessing, wasStale: isStale)
    }

    private func verifyDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExportError.destinationAccessDenied(url.path)
        }
        guard isDirectory.boolValue else {
            throw ExportError.destinationNotADirectory(url.path)
        }
    }
}

extension ExportDestination {
    // `withSecurityScope` is a macOS-only option. On iOS a bookmark taken inside the
    // document picker's scope is already security-scoped, and passing the option there
    // does not compile — hence the split rather than one shared constant.
    #if os(macOS)
    static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let creationOptions: URL.BookmarkCreationOptions = []
    static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    /// The bytes to persist for a folder the caller currently has access to.
    public static func bookmarkData(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: creationOptions,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil)
    }
}

/// A folder an export may write to right now.
///
/// Access is scoped: `release()` must run once the export is done, or the app leaks a
/// sandbox extension. `ExportService` always pairs it with a `defer`.
public struct ResolvedFolder: Sendable {
    public let url: URL
    public let isAccessing: Bool
    /// True when the bookmark had gone stale and was refreshed on this resolve.
    public let wasStale: Bool

    public func release() {
        if isAccessing { url.stopAccessingSecurityScopedResource() }
    }
}
