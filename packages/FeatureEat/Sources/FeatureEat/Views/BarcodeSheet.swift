import AscensionCore
import DesignSystem
import SwiftUI

/// Scan a barcode, or type it.
///
/// The typed field is not a fallback for failure — it is always there, as it is in
/// MacroFactor and MyFitnessPal, because a barcode that will not read is common and a
/// camera that is unavailable (no permission, no device, the simulator) must not end
/// the path. A found product goes to the portion sheet like every other remote food.
struct BarcodeSheet: View {
    let model: EatModel

    @State private var typed = ""
    @State private var found: FoodItemDTO?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if BarcodeScanner.isAvailable {
                    BarcodeScanner(isPaused: found != nil) { code in
                        lookUp(code)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }

                Form {
                    Section {
                        LabeledContent("Barcode") {
                            TextField("Barcode", text: $typed)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .onSubmit { lookUp(typed) }
                        }
                        Button("Look up") { lookUp(typed) }
                            .disabled(typed.count < 8)
                    }
                    if let message = model.barcodeState.message {
                        Section { Text(message) }
                    }
                }
                .frame(maxHeight: BarcodeScanner.isAvailable ? 220 : .infinity)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $found) { food in
                PortionSheet(food: food, meal: MealKind.current(Date())) { portion, meal in
                    await model.log(portion, meal: meal)
                    dismiss()
                }
            }
        }
    }

    private func lookUp(_ code: String) {
        Task {
            if let food = await model.food(barcode: code) {
                found = food
            }
        }
    }
}

extension EatModel.BarcodeState {
    /// The outcome of a lookup, in as few words as the outcome has. Not a sentence,
    /// not advice, and nothing that describes the control it sits under (rule 1.1).
    var message: String? {
        switch self {
        case .idle, .looking: return nil
        case .notFound: return "Not found"
        case .offline: return "Offline"
        case .failed: return "Failed"
        }
    }
}
