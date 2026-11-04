import AscensionCore
import DesignSystem
import SwiftUI

/// A portion whose macros are editable, used by both paths that need one.
///
/// **Editing a logged row** (tap a diary row) and **confirming a photo estimate** are the
/// same screen: a name, a weight, four numbers and the meal they belong to, with one
/// confirming action. Writing it twice would be two screens to keep in step and two
/// places for the arithmetic to drift, so there is one, and the subtraction test (rule
/// 2.1) says the difference between them is a title and a verb.
///
/// Mobbin: MacroFactor's logged-food detail — the four macros of the portion, editable in
/// place, with the destructive action on the same sheet; Cal AI's result card, where the
/// weight is the control and the macros move with it. Patterns only.
struct MealEditorSheet: View {
    enum Mode {
        /// A row already in the diary. The name belongs to the food it came from.
        case edit(DiaryEntry)
        /// An estimate nothing has accepted yet. The name is a guess, so it is editable.
        case confirm(AnalysedFood)

        var isEstimate: Bool {
            if case .confirm = self { return true }
            return false
        }
    }

    let mode: Mode
    let meal: MealKind
    let confirm: (Portion, MealKind) async -> Void
    var remove: (() async -> Void)?

    @State private var name: String
    @State private var grams: Double
    @State private var macros: Macros
    @State private var chosenMeal: MealKind
    /// The weight at the last rescale, so a finished edit knows what it is scaling from.
    @State private var weighedGrams: Double
    @FocusState private var isWeighing: Bool
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, meal: MealKind,
         confirm: @escaping (Portion, MealKind) async -> Void,
         remove: (() async -> Void)? = nil) {
        self.mode = mode
        self.meal = meal
        self.confirm = confirm
        self.remove = remove
        switch mode {
        case let .edit(entry):
            _name = State(initialValue: entry.foodName)
            _grams = State(initialValue: entry.grams)
            _macros = State(initialValue: entry.macros)
            _chosenMeal = State(initialValue: entry.meal)
            _weighedGrams = State(initialValue: entry.grams)
        case let .confirm(food):
            _name = State(initialValue: food.name)
            _grams = State(initialValue: food.grams)
            _macros = State(initialValue: food.macros)
            _chosenMeal = State(initialValue: meal)
            _weighedGrams = State(initialValue: food.grams)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isConfirmable: Bool {
        !trimmedName.isEmpty && grams > 0 && macros.kcal >= 0
    }

    /// The portion the confirming action logs.
    ///
    /// The macros on screen are the portion's own, so the food behind them is derived
    /// back to per 100 g — the shape every other food in this feature has, and the only
    /// one `Portion` knows how to scale.
    private var portion: Portion? {
        guard grams > 0 else { return nil }
        let per100 = 100 / grams
        let food = FoodItemDTO(id: foodId,
                               name: trimmedName,
                               kcalPer100g: macros.kcal * per100,
                               proteinPer100g: macros.proteinG * per100,
                               fatPer100g: macros.fatG * per100,
                               carbsPer100g: macros.carbsG * per100,
                               source: .custom)
        return Portion(food: food, grams: grams)
    }

    /// An edited row keeps its food when nothing about the food changed, so a staple
    /// stays a staple in the export and in recents.
    private var foodId: String {
        if case let .edit(entry) = mode, let existing = entry.foodId,
           trimmedName == entry.foodName {
            return existing
        }
        return "custom_\(UUID().uuidString)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if mode.isEstimate {
                        TextField("Name", text: $name)
                    }
                    field("Grams", value: $grams, unit: "g")
                        .focused($isWeighing)
                    Picker("Meal", selection: $chosenMeal) {
                        ForEach(MealKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                }

                Section {
                    field("Protein", value: $macros.proteinG, unit: "g")
                    field("Calories", value: $macros.kcal, unit: "kcal")
                    field("Fat", value: $macros.fatG, unit: "g")
                    field("Carbs", value: $macros.carbsG, unit: "g")
                } header: {
                    // The only provenance on screen, and one word of it (rule 1.3): a
                    // model's figures are a guess, and the header of the section holding
                    // them is the honest place to say so. An edited diary row carries no
                    // header, because its numbers are the user's own.
                    if mode.isEstimate {
                        Text("Estimate")
                    }
                }

                if let remove {
                    Section {
                        Button("Delete", role: .destructive) {
                            dismiss()
                            Task { await remove() }
                        }
                    }
                }
            }
            // Rescaling happens when the weight field is finished with, not on every
            // keystroke: a partially typed "1" of "150" would otherwise divide the whole
            // plate by two on its way past.
            .onChange(of: isWeighing) { wasWeighing, _ in
                if wasWeighing { rescale(to: grams) }
            }
            .navigationTitle(mode.isEstimate ? trimmedName : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isEstimate ? "Log" : "Save") {
                        guard let portion else { return }
                        let meal = chosenMeal
                        dismiss()
                        Task { await confirm(portion, meal) }
                    }
                    .disabled(!isConfirmable)
                }
            }
        }
    }

    /// Changing the weight moves the macros with it, which is what a portion control
    /// means. Editing a macro directly leaves the weight alone — the user is correcting
    /// the estimate, not reweighing the plate.
    private func rescale(to newGrams: Double) {
        guard weighedGrams > 0, newGrams > 0, newGrams != weighedGrams else {
            weighedGrams = max(0, newGrams)
            return
        }
        let factor = newGrams / weighedGrams
        macros = Macros(kcal: macros.kcal * factor,
                        proteinG: macros.proteinG * factor,
                        fatG: macros.fatG * factor,
                        carbsG: macros.carbsG * factor)
        weighedGrams = newGrams
    }

    private func field(_ label: String, value: Binding<Double>, unit: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: Spacing.tight) {
                TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
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
