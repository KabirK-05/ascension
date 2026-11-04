import AscensionCore
import Foundation

/// One diary entry in the export. `DayRollup` carries the day's nutrition totals but
/// not what was eaten, so the per-meal detail travels as its own entity.
///
/// Field names follow the `log_meal` payload in `docs/EXPORT_SCHEMA.md` §3 — the shape
/// Muse already writes — with the envelope's `date` and `meal` folded into each row so
/// the entity stands alone in `meals[]` and in `meals.csv`.
public struct MealEntry: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var meal: MealKind
    /// The `FoodItem` this came from, or `nil` for a one-off manual entry.
    public var foodItemId: String?
    /// Kept alongside the id so a deleted food still leaves a readable row.
    public var name: String
    public var grams: Double
    public var kcal: Double
    public var proteinG: Double
    public var fatG: Double
    public var carbsG: Double

    public init(date: CalendarDate, meal: MealKind, foodItemId: String? = nil,
                name: String, grams: Double, kcal: Double, proteinG: Double,
                fatG: Double, carbsG: Double) {
        self.date = date
        self.meal = meal
        self.foodItemId = foodItemId
        self.name = name
        self.grams = grams
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(meal, forKey: .meal)
        try container.encodeNullable(foodItemId, forKey: .foodItemId)
        try container.encode(name, forKey: .name)
        try container.encode(grams, forKey: .grams)
        try container.encode(kcal, forKey: .kcal)
        try container.encode(proteinG, forKey: .proteinG)
        try container.encode(fatG, forKey: .fatG)
        try container.encode(carbsG, forKey: .carbsG)
    }
}

extension MealEntry {
    public var macros: Macros {
        Macros(kcal: kcal, proteinG: proteinG, fatG: fatG, carbsG: carbsG)
    }
}
