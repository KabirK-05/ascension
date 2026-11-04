import Foundation

/// A meal on its way into Apple Health (spec §F3: "so the data lives in Apple Health
/// even if this app is deleted").
///
/// `FeatureEat` does not depend on `HealthBridge` — features depend on Core, Engines
/// and DesignSystem only — so the write-back it needs is declared here and the app
/// shell injects `HealthBridge.HealthWriter` behind it. The shape deliberately mirrors
/// `NutritionEntry`: `id` is the idempotency key the writer turns into a HealthKit
/// sync identifier, so writing the same entry twice replaces rather than duplicates.
public struct NutritionSample: Hashable, Sendable, Identifiable {
    public let id: String
    public let consumedAt: Date
    public let energyKcal: Double?
    public let proteinG: Double?
    public let carbsG: Double?
    public let fatG: Double?
    public let waterMl: Double?

    public init(id: String, consumedAt: Date, energyKcal: Double? = nil,
                proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil,
                waterMl: Double? = nil) {
        self.id = id
        self.consumedAt = consumedAt
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.waterMl = waterMl
    }
}

/// What a write actually did. Reported rather than thrown, because a partially
/// authorised write is a real outcome worth showing on the row.
public enum NutritionWriteOutcome: Hashable, Sendable {
    case written
    case partial
    case unavailable
}

extension NutritionWriteOutcome {
    public var diaryState: HealthWriteState {
        switch self {
        case .written: return .written
        case .partial: return .partial
        case .unavailable: return .notWritten
        }
    }
}

/// What a removal actually did.
///
/// `partial` mirrors `NutritionWriteOutcome.partial` and means the same thing: HealthKit
/// authorisation is per type, and a scope the user refused was never written either, so
/// nothing of ours is left behind under it. A partial removal is therefore a complete
/// one as far as this app's data goes.
public enum NutritionRemovalOutcome: Hashable, Sendable {
    case removed
    case partial
    /// Nothing could be reached. The caller must **not** drop its local row on this —
    /// the diary and Apple Health would then disagree silently, which is the ASC-24 bug.
    case unavailable
}

public protocol NutritionWriteBack: Sendable {
    func write(_ sample: NutritionSample) async throws -> NutritionWriteOutcome

    /// Takes a previously written sample back out of Apple Health (ASC-24).
    ///
    /// `sampleId` is the same id `write` was given: the write-back turns it into the
    /// HealthKit sync identifier, so a removal finds exactly the samples that write
    /// produced rather than guessing by timestamp.
    func remove(sampleId: String) async throws -> NutritionRemovalOutcome
}

extension NutritionWriteBack {
    /// The honest default for a write-back that only knows how to add. A shell that has
    /// not injected a removal says `unavailable`, and the caller keeps its row.
    public func remove(sampleId: String) async throws -> NutritionRemovalOutcome {
        .unavailable
    }
}

/// The default until the app shell injects `HealthBridge`.
///
/// It reports honestly rather than pretending: a meal logged through it is in the
/// diary and is not in Apple Health, and the row says so.
public struct UnavailableNutritionWriteBack: NutritionWriteBack {
    public init() {}

    public func write(_ sample: NutritionSample) async throws -> NutritionWriteOutcome {
        .unavailable
    }
}

extension DiaryEntry {
    /// The sample this entry writes. Water is not part of a meal log — F4 owns the
    /// water quick-log — so it is left nil here.
    public var nutritionSample: NutritionSample {
        NutritionSample(id: id, consumedAt: loggedAt, energyKcal: macros.kcal,
                        proteinG: macros.proteinG, carbsG: macros.carbsG,
                        fatG: macros.fatG)
    }
}
