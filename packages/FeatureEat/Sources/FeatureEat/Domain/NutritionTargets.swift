import AscensionCore
import Foundation

/// The day's macro targets (spec §2), in the units the whole app uses.
///
/// Carbohydrate is not a target the user sets — it is the remainder once protein and
/// fat are paid for — so it is derived here rather than stored, and derived once so the
/// diary header and the tests cannot disagree about it.
public struct NutritionTargets: Hashable, Sendable {
    public let kcal: Double
    public let proteinG: Double
    /// The floor the day must clear (140 g), below the 150 g target.
    public let proteinFloorG: Double
    public let fatMinG: Double
    public let fatMaxG: Double

    public init(kcal: Double, proteinG: Double, proteinFloorG: Double,
                fatMinG: Double, fatMaxG: Double) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.proteinFloorG = proteinFloorG
        self.fatMinG = fatMinG
        self.fatMaxG = fatMaxG
    }

    public init(_ targets: GoalTargets) {
        self.init(kcal: Double(targets.kcal),
                  proteinG: Double(targets.proteinG),
                  proteinFloorG: Double(targets.proteinMinG),
                  fatMinG: Double(targets.fatMinG),
                  fatMaxG: Double(targets.fatMaxG))
    }

    /// Spec §2 seed targets, used by previews and as the fallback when no
    /// `GoalSettings` document has been read yet.
    public static let seeded = NutritionTargets(Seed.goalSettings.targets)

    /// The midpoint of the fat range, which is what the carbohydrate remainder is
    /// costed against — the floor would overstate carbs and the ceiling understate them.
    public var fatMidpointG: Double { (fatMinG + fatMaxG) / 2 }

    /// Carbohydrate is whatever the calorie target has left after protein and fat,
    /// at 4 / 9 / 4 kcal per gram. Never negative: a target that cannot pay for its own
    /// protein and fat is a settings problem, not a diary one.
    public var carbsG: Double {
        max(0, (kcal - proteinG * 4 - fatMidpointG * 9) / 4)
    }
}
