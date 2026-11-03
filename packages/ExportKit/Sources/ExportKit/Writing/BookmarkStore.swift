import Foundation

/// Where the chosen folder's bookmark bytes live between launches.
///
/// A protocol rather than a direct `UserDefaults` call so a test can run the whole
/// resolve-and-refresh path against an in-memory store, with no shared defaults domain
/// to leak between tests.
public protocol BookmarkStore: Sendable {
    func loadBookmark() -> Data?
    func saveBookmark(_ data: Data) throws
    func clearBookmark()
}

/// The app's store: one key in `UserDefaults`.
///
/// `UserDefaults` is thread-safe but not `Sendable`, so the conformance is unchecked
/// here rather than propagated through the protocol.
public final class UserDefaultsBookmarkStore: BookmarkStore, @unchecked Sendable {
    public static let defaultKey = "ascension.export.destinationBookmark"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = UserDefaultsBookmarkStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func loadBookmark() -> Data? { defaults.data(forKey: key) }

    public func saveBookmark(_ data: Data) throws { defaults.set(data, forKey: key) }

    public func clearBookmark() { defaults.removeObject(forKey: key) }
}

/// A store that lives only as long as the test holding it.
public final class InMemoryBookmarkStore: BookmarkStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bookmark: Data?

    public init(bookmark: Data? = nil) {
        self.bookmark = bookmark
    }

    public func loadBookmark() -> Data? {
        lock.withLock { bookmark }
    }

    public func saveBookmark(_ data: Data) throws {
        lock.withLock { bookmark = data }
    }

    public func clearBookmark() {
        lock.withLock { bookmark = nil }
    }
}
