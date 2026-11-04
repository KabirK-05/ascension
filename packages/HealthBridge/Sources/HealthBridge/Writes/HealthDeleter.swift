import Foundation

/// Taking samples back out of Apple Health (ASC-24).
///
/// `HealthWriter` only ever added. A meal deleted from the diary therefore left its
/// dietary energy, protein, carbohydrate and fat samples behind in Apple Health, and
/// the app and Health silently disagreed about the day from then on. This is the other
/// half of the write-back.
///
/// **How samples are found.** Not by timestamp — two meals logged in the same minute
/// would be indistinguishable, and a sample edited in Health would move. Every sample
/// `HealthWriter` saves carries `HKMetadataKeySyncIdentifier`, built deterministically by
/// `HealthSampleFactory.syncIdentifier(entryId:metric:)` from the entry id and the metric.
/// A delete reconstructs exactly those identifiers and asks HealthKit for the objects
/// holding them, so it removes the samples belonging to one diary entry and nothing else.
///
/// **What it can remove.** HealthKit only lets an app delete samples it saved itself, so
/// this reaches the app's own writes and nothing a user or another app entered. That is
/// the correct limit, not a gap: a meal this app never wrote is not this app's to remove.
public struct HealthDeleter: Sendable {
    private let store: any HealthSampleDeleting

    public init(store: any HealthSampleDeleting) {
        self.store = store
    }

    /// Removes every sample written for `entryId`.
    ///
    /// Deleting nothing is a success, not a failure: the caller asked for a state — no
    /// samples under this id — and an id HealthKit never saw is already in that state.
    /// An unauthorized metric is reported rather than thrown, matching `HealthWriter`:
    /// a scope the user refused was never written either, so there is nothing of ours
    /// left behind under it.
    @discardableResult
    public func delete(entryId: String,
                       metrics: Set<HealthWriteMetric> = HealthWriteMetric.nutrition)
        async throws -> HealthDeleteReceipt {
        guard store.isHealthDataAvailable else { throw HealthStoreError.healthDataUnavailable }

        var deleted: [HealthWriteMetric: Int] = [:]
        var skipped: [HealthWriteMetric: WriteAuthorization] = [:]
        for metric in metrics.sorted(by: { $0.rawValue < $1.rawValue }) {
            let status = store.writeStatus(for: metric)
            guard status == .granted else {
                skipped[metric] = status
                continue
            }
            let identifier = HealthSampleFactory.syncIdentifier(entryId: entryId, metric: metric)
            deleted[metric] = try await store.deleteSamples(metric: metric,
                                                            syncIdentifiers: [identifier])
        }
        return HealthDeleteReceipt(entryId: entryId, deleted: deleted, skipped: skipped)
    }
}

/// What a delete actually did, per metric. Reported rather than thrown for the same
/// reason `HealthWriteReceipt` is: a partially authorized account is a real situation
/// the Eat screen has to describe, not an error to swallow.
public struct HealthDeleteReceipt: Hashable, Sendable {
    public var entryId: String
    /// Samples removed, per metric. Zero is normal — see `HealthDeleter.delete`.
    public var deleted: [HealthWriteMetric: Int]
    /// Metrics not attempted, and the authorization that stopped them.
    public var skipped: [HealthWriteMetric: WriteAuthorization]

    public init(entryId: String, deleted: [HealthWriteMetric: Int] = [:],
                skipped: [HealthWriteMetric: WriteAuthorization] = [:]) {
        self.entryId = entryId
        self.deleted = deleted
        self.skipped = skipped
    }

    /// Every metric asked for was reachable. The count does not matter.
    public var didReachEveryMetric: Bool { skipped.isEmpty }

    /// Nothing at all was reachable — the user has refused every nutrition scope, so the
    /// app cannot say what Apple Health still holds.
    public var reachedNothing: Bool { deleted.isEmpty && !skipped.isEmpty }

    public var removedCount: Int { deleted.values.reduce(0, +) }
}

/// Deleting samples, as its own seam.
///
/// Deliberately **not** another requirement on `HealthStore`: that protocol is conformed
/// to by the adapter and by fakes in two packages, and widening it would break every one
/// of them for a capability only the Eat write-back needs. `HKHealthStoreAdapter` picks
/// this up in an extension, and `HealthDeleter` takes it rather than the whole store.
public protocol HealthSampleDeleting: Sendable {
    var isHealthDataAvailable: Bool { get }
    func writeStatus(for metric: HealthWriteMetric) -> WriteAuthorization
    /// Removes this app's samples of `metric` carrying any of these sync identifiers,
    /// and answers how many went. Removing none is not an error.
    func deleteSamples(metric: HealthWriteMetric,
                       syncIdentifiers: Set<String>) async throws -> Int
}

extension HealthWriteMetric {
    /// The four a meal writes. Water is logged on its own (F4) and is not part of a meal,
    /// so deleting a meal must not take a glass of water with it.
    public static let nutrition: Set<HealthWriteMetric> = [
        .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat
    ]
}
