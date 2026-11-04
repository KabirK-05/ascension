import AscensionCore
import Foundation

/// What the day adds up to, against what it was supposed to.
///
/// Pure arithmetic over value types, so the header, the widget-shaped figures and the
/// tests all read the same numbers.
public struct DayTotals: Hashable, Sendable {
    public let eaten: Macros
    public let targets: NutritionTargets

    public init(eaten: Macros, targets: NutritionTargets) {
        self.eaten = eaten
        self.targets = targets
    }

    public init(entries: some Sequence<DiaryEntry>, targets: NutritionTargets) {
        self.init(eaten: Macros.total(entries.map(\.macros)), targets: targets)
    }

    /// The number this tab exists for (design rule 2.1). Never negative: past the
    /// target there is nothing left, and the ring's overflow says the rest.
    public var proteinRemainingG: Double { max(0, targets.proteinG - eaten.proteinG) }

    /// Whether the day has cleared the 140 g floor, which is the figure the
    /// consistency grid scores (design rule 6.2).
    public var clearedProteinFloor: Bool { eaten.proteinG >= targets.proteinFloorG }

    public var kcalRemaining: Double { max(0, targets.kcal - eaten.kcal) }

    public var proteinProgress: Double { Self.progress(eaten.proteinG, targets.proteinG) }
    public var kcalProgress: Double { Self.progress(eaten.kcal, targets.kcal) }
    /// Fat is a range, so progress runs to the ceiling: the useful question in the
    /// evening is how much fat is still affordable, not how far past the floor it is.
    public var fatProgress: Double { Self.progress(eaten.fatG, targets.fatMaxG) }
    public var carbsProgress: Double { Self.progress(eaten.carbsG, targets.carbsG) }

    private static func progress(_ value: Double, _ goal: Double) -> Double {
        guard goal > 0, value.isFinite else { return 0 }
        return min(max(value / goal, 0), 1)
    }
}
