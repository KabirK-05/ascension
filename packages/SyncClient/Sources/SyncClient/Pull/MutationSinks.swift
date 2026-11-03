import AscensionCore
import Foundation

/// The HealthKit write-back this package needs, declared here rather than imported.
///
/// `SyncClient` depends on `AscensionCore` and nothing else, so the requirement is a
/// protocol in this package and the app shell satisfies it with `HealthBridge`'s
/// `HealthWriter`. HealthKit can only be written on the device (`docs/TECH_STACK.md` §2.4),
/// which is the whole reason a `log_meal` from Muse waits in D1 until this runs.
///
/// **`entryId` is the mutation's ULID, and the implementation must pass it straight through
/// as the HealthKit sync identifier.** HealthKit replaces a sample whose identifier it
/// already holds, so the same mutation applied twice writes once. Inventing a fresh id per
/// attempt is the one way to double-log a meal.
public protocol HealthWriteBack: Sendable {
    func writeMeal(_ meal: HealthMealWrite) async throws
    func writeWater(millilitres: Double, at instant: Date, entryId: String) async throws
}

/// A meal on its way into Apple Health. Mirrors `HealthBridge.NutritionEntry` field for
/// field, so the adapter in the app shell is a one-liner.
public struct HealthMealWrite: Hashable, Sendable {
    public var entryId: String
    public var consumedAt: Date
    public var energyKcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var waterMl: Double?

    public init(entryId: String, consumedAt: Date, energyKcal: Double? = nil,
                proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil,
                waterMl: Double? = nil) {
        self.entryId = entryId
        self.consumedAt = consumedAt
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.waterMl = waterMl
    }
}

/// The local state a mutation changes: the SwiftData store, the flags, the Watch schedule,
/// the export.
///
/// Every method is keyed by `mutationId`. The drain's ledger already refuses a second
/// delivery, but an implementation that keys its own writes on the id cannot double-apply
/// even if the ledger is lost — so each one receives it.
public protocol LocalStateApplier: Sendable {
    /// Tier 1. The Worker has already bumped the document; this is the local copy catching
    /// up, so the app reads the same targets while offline.
    func applyTargets(_ patch: MutationPayload.TargetsPatch, mutationId: String) async throws
    func applyProgram(_ body: MutationPayload.ProgramBody, mutationId: String) async throws
    func applyStaples(_ staples: [FoodItemDTO], mutationId: String) async throws
    func applyFlag(_ change: MutationPayload.FlagChange, mutationId: String) async throws
    func applySuggestion(_ suggestionId: String, mutationId: String) async throws

    /// Tier 2, the parts that are app-owned rather than HealthKit-owned.
    func applyTopSet(_ payload: MutationPayload.TopSetPayload, mutationId: String) async throws
    func applyCheckIn(_ payload: MutationPayload.CheckInPayload, mutationId: String) async throws
    func scheduleWorkout(_ payload: MutationPayload.ScheduledWorkout,
                         mutationId: String) async throws
    func triggerExport(mutationId: String) async throws

    /// A `log_meal` also belongs in the local meal list, not just in Apple Health: the
    /// rollup's macro totals come from logged meals, and HealthKit is not read back for
    /// them. Called after the HealthKit write succeeds.
    func recordLoggedMeal(_ meal: LoggedMeal, payload: MutationPayload.LoggedMealPayload,
                          mutationId: String) async throws
}
