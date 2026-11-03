import Foundation
import SwiftData

/// A food the user can log, carried per 100 g (spec §7).
@Model
public final class FoodItem {
    @Attribute(.unique) public var id: String = ""
    public var name: String = ""
    public var brand: String?
    public var kcalPer100g: Double = 0
    public var proteinPer100g: Double = 0
    public var fatPer100g: Double = 0
    public var carbsPer100g: Double = 0
    public var source: FoodSource = FoodSource.custom
    public var barcode: String?
    public var servingGrams: Double?
    public var servingName: String?

    public init(id: String, name: String, brand: String? = nil, kcalPer100g: Double,
                proteinPer100g: Double, fatPer100g: Double, carbsPer100g: Double,
                source: FoodSource, barcode: String? = nil,
                servingGrams: Double? = nil, servingName: String? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.fatPer100g = fatPer100g
        self.carbsPer100g = carbsPer100g
        self.source = source
        self.barcode = barcode
        self.servingGrams = servingGrams
        self.servingName = servingName
    }
}

/// One entry in the day's diary. Macros are stored alongside the portion so a later
/// edit to the `FoodItem` cannot silently rewrite history.
@Model
public final class MealLog {
    /// The local day, `YYYY-MM-DD`. Stored as a string so date-range predicates work.
    public var date: String = ""
    public var meal: MealKind = MealKind.snack
    public var grams: Double = 0
    public var kcal: Double = 0
    public var proteinG: Double = 0
    public var fatG: Double = 0
    public var carbsG: Double = 0
    public var foodItem: FoodItem?
    /// Kept even when `foodItem` is nil, so a deleted food leaves a readable entry.
    public var foodName: String = ""

    public init(date: CalendarDate, meal: MealKind, grams: Double, macros: Macros,
                foodItem: FoodItem? = nil, foodName: String) {
        self.date = date.rawValue
        self.meal = meal
        self.grams = grams
        self.kcal = macros.kcal
        self.proteinG = macros.proteinG
        self.fatG = macros.fatG
        self.carbsG = macros.carbsG
        self.foodItem = foodItem
        self.foodName = foodName
    }

    public var calendarDate: CalendarDate? { CalendarDate(rawValue: date) }

    public var macros: Macros {
        Macros(kcal: kcal, proteinG: proteinG, fatG: fatG, carbsG: carbsG)
    }
}
