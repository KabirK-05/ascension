import AscensionCore
import Foundation

@testable import ExportKit

// Spec §2: chicken and eggs are the only meats, milk with Bournvita is the one dairy
// drink, and no pork or beef appears anywhere. These are the seeded staples' own names
// and macros, scaled to the portion logged.
extension Fixture {
    static func monthMeals(date: CalendarDate, offset: Int) -> [MealEntry] {
        guard offset != unloggedOffset else { return [] }
        var entries = [
            staple("staple_omelette_toast", meal: .breakfast, date: date, grams: 315),
            staple("staple_chicken_breast_rice", meal: .lunch, date: date, grams: 550),
            staple("staple_chicken_thighs_potatoes", meal: .dinner, date: date, grams: 600)
        ].compactMap { $0 }
        if offset % 3 == 0, let snack = staple("staple_milk_bournvita", meal: .snack,
                                               date: date, grams: 250) {
            entries.append(snack)
        }
        return entries
    }

    /// A diary row built from a seeded staple, so the names and macros in the fixture
    /// are the app's own data and not a second invention of them.
    static func staple(_ id: String, meal: MealKind, date: CalendarDate,
                       grams: Double) -> MealEntry? {
        guard let food = Seed.stapleFoods.first(where: { $0.id == id }) else { return nil }
        let macros = food.macros(forGrams: grams)
        return MealEntry(date: date, meal: meal, foodItemId: food.id, name: food.name,
                         grams: grams, kcal: rounded(macros.kcal),
                         proteinG: rounded(macros.proteinG),
                         fatG: rounded(macros.fatG), carbsG: rounded(macros.carbsG))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
