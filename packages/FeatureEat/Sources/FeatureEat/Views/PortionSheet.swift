import AscensionCore
import DesignSystem
import SwiftUI

/// Confirm the portion, then log.
///
/// Every path except a staple tap ends here, and that is deliberate: a barcode or a
/// search result carries macros this app did not compute, and nothing a remote source
/// said reaches Apple Health until the user has looked at the portion it applies to.
/// The arrangement follows Cal AI and MacroFactor — the resulting macros update as the
/// portion changes, so the figure being confirmed is the figure that lands.
struct PortionSheet: View {
    let food: FoodItemDTO
    let meal: MealKind
    let log: (Portion, MealKind) async -> Void

    @State private var grams: Double
    @State private var chosenMeal: MealKind
    @Environment(\.dismiss) private var dismiss

    init(food: FoodItemDTO, meal: MealKind, log: @escaping (Portion, MealKind) async -> Void) {
        self.food = food
        self.meal = meal
        self.log = log
        _grams = State(initialValue: food.servingGrams ?? 100)
        _chosenMeal = State(initialValue: meal)
    }

    private var portion: Portion { Portion(food: food, grams: grams) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Grams") {
                        TextField("Grams", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    Picker("Meal", selection: $chosenMeal) {
                        ForEach(MealKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                }

                Section {
                    ValueRow("Protein", value: Figure.whole(portion.macros.proteinG), unit: "g")
                    ValueRow("Calories", value: Figure.whole(portion.macros.kcal), unit: "kcal")
                    ValueRow("Fat", value: Figure.whole(portion.macros.fatG), unit: "g")
                    ValueRow("Carbs", value: Figure.whole(portion.macros.carbsG), unit: "g")
                }
            }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let portion = portion
                        let meal = chosenMeal
                        dismiss()
                        Task { await log(portion, meal) }
                    }
                    .disabled(grams <= 0)
                }
            }
        }
    }
}
