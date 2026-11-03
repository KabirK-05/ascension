import Foundation

/// A bounded record of the sample UUIDs a callback has already acted on.
///
/// Observer queries fire more than once for the same data — on registration, on a
/// duplicate background wake, after a relaunch — so "have I seen this sample?" has to be
/// answerable without re-deriving everything. The ledger is bounded because it is kept in
/// a defaults blob, not a database: the oldest ids fall off, and a sample that old
/// arriving again is handled by the mirrors' own upsert-on-UUID instead.
public struct IdempotencyLedger: Hashable, Sendable {
    public private(set) var ids: [String]
    public let capacity: Int

    public init(ids: [String] = [], capacity: Int = 512) {
        self.capacity = max(1, capacity)
        self.ids = Array(ids.suffix(self.capacity))
    }

    public func contains(_ id: UUID) -> Bool { ids.contains(id.uuidString) }

    /// The ids not seen before, in the order given, with duplicates inside the batch
    /// collapsed. Marks them seen.
    public mutating func admit(_ incoming: [UUID]) -> [UUID] {
        var known = Set(ids)
        var fresh: [UUID] = []
        for id in incoming where known.insert(id.uuidString).inserted {
            fresh.append(id)
        }
        guard !fresh.isEmpty else { return [] }
        ids = Array((ids + fresh.map(\.uuidString)).suffix(capacity))
        return fresh
    }

    /// Drops ids so a deleted sample can be processed again if HealthKit resurrects it.
    public mutating func forget(_ outgoing: [UUID]) {
        let dropped = Set(outgoing.map(\.uuidString))
        ids.removeAll { dropped.contains($0) }
    }
}

/// Anchors and seen-sample ledgers, per metric. Persisting them is the app shell's job;
/// `InMemorySyncState` is the default and is what the tests use.
public protocol HealthSyncState: Sendable {
    func anchor(for metric: HealthMetric) async -> HealthAnchorToken?
    func setAnchor(_ anchor: HealthAnchorToken?, for metric: HealthMetric) async
    /// Records and returns the ids not seen before for this metric.
    func admit(_ ids: [UUID], for metric: HealthMetric) async -> [UUID]
    func forget(_ ids: [UUID], for metric: HealthMetric) async
}

/// The default `HealthSyncState`: correct, and forgotten on relaunch. A relaunch costs a
/// re-read, which the mirrors absorb because every one of them upserts on UUID.
public actor InMemorySyncState: HealthSyncState {
    private var anchors: [HealthMetric: HealthAnchorToken] = [:]
    private var ledgers: [HealthMetric: IdempotencyLedger] = [:]
    private let capacity: Int

    public init(capacity: Int = 512) {
        self.capacity = capacity
    }

    public func anchor(for metric: HealthMetric) async -> HealthAnchorToken? { anchors[metric] }

    public func setAnchor(_ anchor: HealthAnchorToken?, for metric: HealthMetric) async {
        if let anchor {
            anchors[metric] = anchor
        } else {
            anchors.removeValue(forKey: metric)
        }
    }

    public func admit(_ ids: [UUID], for metric: HealthMetric) async -> [UUID] {
        var ledger = ledgers[metric] ?? IdempotencyLedger(capacity: capacity)
        let fresh = ledger.admit(ids)
        ledgers[metric] = ledger
        return fresh
    }

    public func forget(_ ids: [UUID], for metric: HealthMetric) async {
        guard var ledger = ledgers[metric] else { return }
        ledger.forget(ids)
        ledgers[metric] = ledger
    }
}
