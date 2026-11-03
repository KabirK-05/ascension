import Foundation

/// Everything the drain must remember across a restart.
///
/// `cursor` alone is not enough. A mutation can be applied and the ack can then fail — the
/// phone goes offline between the HealthKit write and the `POST` — and the Worker will
/// deliver it again. ``appliedIds`` is what makes the second delivery a no-op, which is why
/// it is persisted with the cursor rather than held in memory.
public struct SyncState: Codable, Hashable, Sendable {
    /// The `since` value for the next `GET /v1/mutations`.
    public var cursor: String?
    /// Ids already applied, newest last. Capped: the cursor covers everything older.
    public var appliedIds: [String]
    /// How many times each id has failed to apply, so a poison pill is visible rather
    /// than silently retried forever.
    public var failures: [String: Int]

    public init(cursor: String? = nil, appliedIds: [String] = [], failures: [String: Int] = [:]) {
        self.cursor = cursor
        self.appliedIds = appliedIds
        self.failures = failures
    }

    /// How many applied ids are kept. Generous next to a drain's handful, and small enough
    /// that the file stays a few kilobytes.
    public static let ledgerLimit = 500

    public func hasApplied(_ id: String) -> Bool {
        appliedIds.contains(id)
    }

    public func recordingApplied(_ id: String) -> SyncState {
        var copy = self
        if !copy.appliedIds.contains(id) { copy.appliedIds.append(id) }
        copy.appliedIds = copy.appliedIds.sorted().suffix(Self.ledgerLimit)
        copy.failures[id] = nil
        return copy
    }

    public func recordingFailure(_ id: String) -> SyncState {
        var copy = self
        copy.failures[id, default: 0] += 1
        return copy
    }

    public func advancingCursor(to cursor: String) -> SyncState {
        var copy = self
        // ULIDs sort lexicographically, so a cursor only ever moves forward.
        if let current = copy.cursor, current >= cursor { return copy }
        copy.cursor = cursor
        return copy
    }
}

/// Where ``SyncState`` is kept. A protocol so the drain can be tested without a filesystem,
/// and so "survives a restart" can be asserted by handing a second drainer the same store.
public protocol SyncStateStore: Sendable {
    func load() throws -> SyncState
    func save(_ state: SyncState) throws
}

/// State in memory. Shared by reference so two drainers can be pointed at one store, which
/// is how the restart test works.
public final class InMemorySyncStateStore: SyncStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SyncState

    public init(state: SyncState = SyncState()) {
        self.state = state
    }

    public func load() throws -> SyncState {
        lock.withLock { state }
    }

    public func save(_ state: SyncState) throws {
        lock.withLock { self.state = state }
    }
}
