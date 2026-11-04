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
///
/// **Both methods report what landed.** HealthKit refuses a scope by declining the field,
/// not by throwing — `HealthBridge.HealthWriter` reports it in a receipt instead, which is
/// right for the Eat screen, where a partially written meal is an outcome a row shows. The
/// drain needs the same fact for the opposite reason: a meal that did not reach Apple Health
/// must not be acked as applied (ASC-27). An implementation that swallows the receipt and
/// returns nothing is how this went wrong the first time, so there is nothing to swallow.
public protocol HealthWriteBack: Sendable {
    func writeMeal(_ meal: HealthMealWrite) async throws -> HealthWriteOutcome
    func writeWater(millilitres: Double, at instant: Date,
                    entryId: String) async throws -> HealthWriteOutcome
}

/// What a write to Apple Health actually achieved.
///
/// Metrics are named as strings rather than as `HealthBridge.HealthWriteMetric`: this
/// package depends on `AscensionCore` and nothing else, and the names exist here only to be
/// shown to the user, never matched on.
public struct HealthWriteOutcome: Hashable, Sendable {
    /// Metrics that reached Apple Health.
    public var savedMetrics: [String]
    /// Metrics that did not: a refused scope, or a value HealthKit would not take.
    public var refusedMetrics: [String]

    public init(savedMetrics: [String] = [], refusedMetrics: [String] = []) {
        self.savedMetrics = savedMetrics
        self.refusedMetrics = refusedMetrics
    }

    /// Everything the mutation carried is now in Apple Health.
    ///
    /// Deliberately all-or-nothing. A meal whose protein landed and whose energy did not is
    /// divergence just as much as one that landed nowhere, and the retry costs nothing: the
    /// sync identifier makes a second attempt a replacement rather than a second meal.
    public var reachedEverything: Bool { refusedMetrics.isEmpty && !savedMetrics.isEmpty }
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
    /// them.
    ///
    /// **Called only when the meal reached Apple Health in full.** The rule a row here
    /// carries: it is a claim that Apple Health holds this meal. A write Health refused
    /// gets ``recordRefusedHealthWrite(_:mutationId:)`` instead, and no row.
    func recordLoggedMeal(_ meal: LoggedMeal, payload: MutationPayload.LoggedMealPayload,
                          mutationId: String) async throws

    /// A `log_meal` or `log_water` this device has given up on writing to Apple Health.
    ///
    /// The end of the road for ASC-27: the write was attempted
    /// ``MutationApplier/healthWriteAttemptLimit`` times, Apple Health declined it every
    /// time, and the drain acks it rather than letting one refused scope block every
    /// mutation behind it forever. Acking a write that never landed is only honest if the
    /// user is told, so this is the telling — and it has to reach somewhere a person
    /// actually looks, not a log line.
    ///
    /// No local meal row accompanies it. `FeatureEat` already keeps an unwritten meal out
    /// of the diary when every nutrition scope is refused; the same rule holds here, and
    /// the app would rather be missing a meal than hold one Apple Health does not.
    func recordRefusedHealthWrite(_ refusal: RefusedHealthWrite,
                                  mutationId: String) async throws
}

/// A Tier-2 write Apple Health would not take, in the terms the app shell needs in order to
/// tell the user about it.
public struct RefusedHealthWrite: Hashable, Sendable {
    /// What Muse was trying to log.
    public var subject: Subject
    /// The metric names Apple Health declined, for the row the user reads.
    public var refusedMetrics: [String]
    /// How many times this device tried before giving up.
    public var attempts: Int

    public init(subject: Subject, refusedMetrics: [String], attempts: Int) {
        self.subject = subject
        self.refusedMetrics = refusedMetrics
        self.attempts = attempts
    }

    /// The payload is carried whole rather than summarised: the shell writes the user-facing
    /// line, and this package has no business choosing those words.
    public enum Subject: Hashable, Sendable {
        case meal(MutationPayload.LoggedMealPayload)
        case water(millilitres: Double)
    }
}
