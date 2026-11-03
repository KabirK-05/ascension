import Foundation

/// The write-back surface (spec §6, F3, F4).
///
/// Seven sample types, nothing else. This is the only path by which a meal Muse logged
/// reaches Apple Health — HealthKit cannot be written from off the device — so ASC-12
/// calls straight into here when it applies a Tier-2 mutation.
///
/// **Idempotency.** Every sample carries an `HKMetadataKeySyncIdentifier` derived from the
/// entry id and the metric, plus an `HKMetadataKeySyncVersion`. HealthKit replaces a
/// previously saved sample that has the same sync identifier instead of adding a second
/// one, so repeating a write with the same entry id cannot double-log a meal. The
/// guarantee holds only for samples this app saved: HealthKit will not replace a sample
/// another app owns, and it does not deduplicate across different entry ids. A caller
/// that invents a fresh id per attempt gets duplicates, by its own choice.
public struct HealthWriter: Sendable {
    private let store: any HealthStore

    public init(store: any HealthStore) {
        self.store = store
    }

    /// Writes a meal's macros, and water when the entry carries it.
    @discardableResult
    public func write(_ entry: NutritionEntry) async throws -> HealthWriteReceipt {
        let built = HealthSampleFactory.samples(for: entry)
        return try await save(entryId: entry.id, built: built)
    }

    /// Writes a manual weight or waist measurement.
    @discardableResult
    public func write(_ entry: BodyMeasurementEntry) async throws -> HealthWriteReceipt {
        let built = HealthSampleFactory.samples(for: entry)
        return try await save(entryId: entry.id, built: built)
    }

    /// Water on its own, which is the quick-log in F4.
    @discardableResult
    public func writeWater(millilitres: Double, at instant: Date,
                           entryId: String) async throws -> HealthWriteReceipt {
        try await write(NutritionEntry(id: entryId, consumedAt: instant, waterMl: millilitres))
    }

    private func save(entryId: String,
                      built: (saved: [WriteSample], skipped: [HealthWriteMetric: WriteSkip]))
        async throws -> HealthWriteReceipt {
        guard store.isHealthDataAvailable else { throw HealthStoreError.healthDataUnavailable }

        var skipped = built.skipped
        var writable: [WriteSample] = []
        for sample in built.saved {
            let status = store.writeStatus(for: sample.metric)
            // An unauthorized field is reported, not thrown: a user who allowed protein
            // and refused water should still get the protein written.
            if status == .granted {
                writable.append(sample)
            } else {
                skipped[sample.metric] = .notAuthorized(status)
            }
        }

        if !writable.isEmpty {
            try await store.save(writable)
        }
        return HealthWriteReceipt(entryId: entryId, saved: writable, skipped: skipped)
    }
}
