import Foundation

extension Seed {
    /// The four staples (spec §2), seeded as one-tap quick-add rows.
    ///
    /// Macros are carried per 100 g like every other food so portion scaling is uniform;
    /// `servingGrams` is the portion spec §2 describes, and multiplying the two returns
    /// the kcal and protein figures it quotes. Chicken and eggs are the only meats here,
    /// and the only dairy is milk with Bournvita.
    public static let stapleFoods: [FoodItemDTO] = [
        FoodItemDTO(
            id: "staple_omelette_toast",
            name: "3-egg omelette, veggies, 2 toast",
            kcalPer100g: 136.5,
            proteinPer100g: 7.6,
            fatPer100g: 6.7,
            carbsPer100g: 11.4,
            source: .staple,
            servingGrams: 315,
            servingName: "1 plate"),
        FoodItemDTO(
            id: "staple_chicken_breast_rice",
            name: "Chicken breast, rice, vegetables",
            kcalPer100g: 118.2,
            proteinPer100g: 10.0,
            fatPer100g: 2.5,
            carbsPer100g: 13.8,
            source: .staple,
            servingGrams: 550,
            servingName: "1 plate"),
        FoodItemDTO(
            id: "staple_chicken_thighs_potatoes",
            name: "Chicken thighs, potatoes, salad",
            kcalPer100g: 116.7,
            proteinPer100g: 8.3,
            fatPer100g: 4.8,
            carbsPer100g: 10.0,
            source: .staple,
            servingGrams: 600,
            servingName: "1 plate"),
        FoodItemDTO(
            id: "staple_milk_bournvita",
            name: "Milk with Bournvita",
            kcalPer100g: 92.6,
            proteinPer100g: 3.7,
            fatPer100g: 3.0,
            carbsPer100g: 13.0,
            source: .staple,
            servingGrams: 270,
            servingName: "1 glass")
    ]
}
