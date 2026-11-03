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

public protocol NutritionWriteBack: Sendable {
    func write(_ sample: NutritionSample) async throws -> NutritionWriteOutcome
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
