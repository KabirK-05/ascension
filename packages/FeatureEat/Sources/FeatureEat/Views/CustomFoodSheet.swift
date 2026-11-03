import AscensionCore
import DesignSystem
import SwiftUI

/// A food the user types, per 100 g like every other food, so it scales by grams the
/// same way (spec §F3).
///
/// It is also the path that works with no network, no key and no camera, which is why
/// it is one menu item away rather than buried behind a failed search.
struct CustomFoodSheet: View {
    let model: EatModel

    @State private var name = ""
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var fat: Double = 0
    @State private var carbs: Double = 0
    @State private var grams: Double = 100
    @State private var meal: MealKind = MealKind.current(Date())
    @Environment(\.dismiss) private var dismiss

    private var food: FoodItemDTO {
        FoodItemDTO(id: "custom_\(UUID().uuidString)",
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    kcalPer100g: kcal,
                    proteinPer100g: protein,
                    fatPer100g: fat,
                    carbsPer100g: carbs,
                    source: .custom)
    }

    private var isLoggable: Bool {
        !food.name.isEmpty && grams > 0 && kcal >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section("Per 100 g") {
                    field("Calories", value: $kcal, unit: "kcal")
                    field("Protein", value: $protein, unit: "g")
                    field("Fat", value: $fat, unit: "g")
                    field("Carbs", value: $carbs, unit: "g")
                }
                Section {
                    field("Grams", value: $grams, unit: "g")
                    Picker("Meal", selection: $meal) {
                        ForEach(MealKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                }
            }
            .navigationTitle("Custom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let portion = Portion(food: food, grams: grams)
                        let meal = meal
                        dismiss()
                        Task { await model.log(portion, meal: meal) }
                    }
                    .disabled(!isLoggable)
                }
            }
        }
    }

    private func field(_ label: String, value: Binding<Double>, unit: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: Spacing.tight) {
                TextField(label, value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(unit)
                    .font(Typography.unit)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
}
