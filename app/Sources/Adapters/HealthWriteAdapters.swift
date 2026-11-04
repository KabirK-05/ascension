import FeatureEat
import Foundation
import HealthBridge
import SyncClient

/// `FeatureEat`'s write-back, satisfied by `HealthBridge`.
///
/// `FeatureEat` may not import `HealthBridge` — a feature depends on Core, Engines and
/// DesignSystem only — so it declares the protocol and the shell is the one place that
/// knows a meal ends up in `HKHealthStore`. The field names already line up; the only real
/// work is mapping the receipt back, because a partially authorised write is a real outcome
/// the diary row shows rather than an error to throw.
struct NutritionWriteBackAdapter: FeatureEat.NutritionWriteBack {
    private let writer: HealthWriter
    private let deleter: HealthDeleter

    init(writer: HealthWriter, deleter: HealthDeleter) {
        self.writer = writer
        self.deleter = deleter
    }

    func write(_ sample: FeatureEat.NutritionSample) async throws -> NutritionWriteOutcome {
        let entry = HealthBridge.NutritionEntry(
            id: sample.id,
            consumedAt: sample.consumedAt,
            energyKcal: sample.energyKcal,
            proteinG: sample.proteinG,
            carbsG: sample.carbsG,
            fatG: sample.fatG,
            waterMl: sample.waterMl)
        let receipt = try await writer.write(entry)
        if receipt.didSaveEverything { return .written }
        return receipt.saved.isEmpty ? .unavailable : .partial
    }

    /// Takes a meal back out of Apple Health (ASC-24).
    ///
    /// `sampleId` is the same id `write` was given, which is what makes this exact:
    /// `HealthBridge` rebuilds the sync identifiers that write produced and deletes the
    /// objects holding them. Nothing here guesses by timestamp, and nothing here touches
    /// water — F4 owns that, and a meal is not a glass of water.
    ///
    /// The receipt maps the way the write's does, and `reachedNothing` is the case that
    /// matters: every nutrition scope refused, so the app cannot say what Health still
    /// holds, and `FeatureEat` keeps its row rather than letting the two diverge.
    func remove(sampleId: String) async throws -> NutritionRemovalOutcome {
        let receipt = try await deleter.delete(entryId: sampleId)
        if receipt.reachedNothing { return .unavailable }
        return receipt.didReachEveryMetric ? .removed : .partial
    }
}

/// `SyncClient`'s write-back, satisfied by `HealthBridge`.
///
/// This is the path that makes a meal Muse logged real: HealthKit can only be written on
/// the device (`docs/TECH_STACK.md` §2.4), so a `log_meal` waits in D1 until the drain runs
/// and calls through here.
///
/// **`entryId` is passed straight through as the sample's identity.** It is the mutation's
/// ULID, `HealthBridge` turns it into the HealthKit sync identifier, and HealthKit replaces
/// a sample it already holds under that identifier. Minting a fresh id per attempt is the
/// one way to double-log a meal, so nothing here invents one.
struct HealthMutationWriteBack: SyncClient.HealthWriteBack {
    private let writer: HealthWriter

    init(writer: HealthWriter) {
        self.writer = writer
    }

    func writeMeal(_ meal: HealthMealWrite) async throws {
        try await writer.write(HealthBridge.NutritionEntry(
            id: meal.entryId,
            consumedAt: meal.consumedAt,
            energyKcal: meal.energyKcal,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            waterMl: meal.waterMl))
    }

    func writeWater(millilitres: Double, at instant: Date, entryId: String) async throws {
        try await writer.writeWater(millilitres: millilitres, at: instant, entryId: entryId)
    }
}
