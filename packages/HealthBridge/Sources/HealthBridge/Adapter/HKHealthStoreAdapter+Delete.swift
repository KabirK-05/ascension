#if canImport(HealthKit)
import Foundation
import HealthKit

/// The real deletion, kept beside the adapter rather than inside it: `HealthStore` is a
/// read-and-write seam several fakes conform to, and ASC-24 needs one capability more
/// without widening that contract. `isHealthDataAvailable` and `writeStatus(for:)` are
/// already on the adapter, so this extension only has to supply the delete itself.
extension HKHealthStoreAdapter: HealthSampleDeleting {

    /// Finds this app's samples by their sync identifier and removes them.
    ///
    /// `predicateForObjects(withMetadataKey:allowedValues:)` matches on the metadata
    /// `HealthWriter` wrote, which is what makes this exact: the predicate selects the
    /// samples of one diary entry and no other. `deleteObjects(of:predicate:)` restricts
    /// itself to objects this app saved, so a sample the user entered in Health by hand,
    /// or one another app owns, is never touched even if it somehow carried the key.
    public func deleteSamples(metric: HealthWriteMetric,
                              syncIdentifiers: Set<String>) async throws -> Int {
        guard !syncIdentifiers.isEmpty else { return 0 }
        let type = HKTypeMapping.quantityType(for: metric)
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                    allowedValues: Array(syncIdentifiers))
        do {
            return try await deleteObjects(of: type, predicate: predicate)
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    /// `HKHealthStore.deleteObjects` is still completion-based, and its error for
    /// "nothing matched" is `errorNoData`, which is the success this caller means.
    private func deleteObjects(of type: HKSampleType,
                               predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            store.deleteObjects(of: type, predicate: predicate) { _, count, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    continuation.resume(returning: 0)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: count)
            }
        }
    }
}
#endif
