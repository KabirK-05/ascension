import AscensionCore
import Foundation

/// A weighed portion of a food, and the macros it carries.
///
/// Every logging path in this feature ends here: a staple tap, a barcode, a USDA
/// search hit and a hand-entered food all become grams of a `FoodItemDTO` before
/// anything is written. One scaling rule, one place to test it.
public struct Portion: Hashable, Sendable {
    public let food: FoodItemDTO
    public let grams: Double

    public init(food: FoodItemDTO, grams: Double) {
        self.food = food
        self.grams = max(0, grams)
    }

    /// The food's own serving, when it has one. A staple tap is exactly this.
    public init?(serving food: FoodItemDTO) {
        guard let servingGrams = food.servingGrams, servingGrams > 0 else { return nil }
        self.init(food: food, grams: servingGrams)
    }

    public var macros: Macros { food.macros(forGrams: grams) }

    /// How many of the food's own servings this portion is, when it has one.
    /// The portion sheet shows grams; this is what makes "1.5 plates" sayable.
    public var servings: Double? {
        guard let servingGrams = food.servingGrams, servingGrams > 0 else { return nil }
        return grams / servingGrams
    }

    public func scaled(toServings servings: Double) -> Portion? {
        guard let servingGrams = food.servingGrams, servingGrams > 0 else { return nil }
        return Portion(food: food, grams: servingGrams * servings)
    }
}

extension Macros {
    public static let zero = Macros(kcal: 0, proteinG: 0, fatG: 0, carbsG: 0)

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal,
               proteinG: lhs.proteinG + rhs.proteinG,
               fatG: lhs.fatG + rhs.fatG,
               carbsG: lhs.carbsG + rhs.carbsG)
    }

    /// Sums a day's worth of portions. Written as a fold rather than four `reduce`
    /// calls so a diary of 20 entries is walked once.
    public static func total(_ macros: some Sequence<Macros>) -> Macros {
        macros.reduce(.zero, +)
    }
}
