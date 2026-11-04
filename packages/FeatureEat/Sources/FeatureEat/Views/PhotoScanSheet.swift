import AscensionCore
import DesignSystem
import SwiftUI

/// Scan → result → confirm, for a plate the barcode scanner cannot read (spec §F3 v2).
///
/// The sequence is Cal AI's and the reason to copy it is the last step: an estimate is
/// shown, and nothing is logged until the user has accepted it. That is what Kabir asked
/// for ("I should be able to edit the macros from there") and it is also what keeps a
/// model's guess out of Apple Health. Every row goes to `MealEditorSheet` before it
/// becomes a diary entry.
///
/// Mobbin: Cal AI "Scanning a food" and "Food detail" — the camera, the analysing state,
/// a result list of name-and-macros rows, and an editable detail behind each. Patterns
/// only; no copy, no icons, no brand assets.
struct PhotoScanSheet: View {
    let model: EatModel

    @State private var found: [AnalysedFood] = []
    @State private var chosen: AnalysedFood?
    @State private var isPicking = false
    @State private var isAskingConsent = false
    @State private var showingKeyField = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                stateSection
                if !found.isEmpty {
                    Section {
                        ForEach(found) { food in
                            row(food)
                        }
                    }
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { start() }
            .fullScreenCover(isPresented: $isPicking) {
                MealPhotoPicker { jpeg in
                    isPicking = false
                    guard let jpeg else { return }
                    Task { found = await model.foods(inPhoto: jpeg) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $chosen) { food in
                MealEditorSheet(mode: .confirm(food),
                                meal: MealKind.current(Date())) { portion, meal in
                    await model.log(portion, meal: meal)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingKeyField) {
                FoodDataSettingsView(keys: model.keyStore, consent: model.photoConsent)
            }
            // The one place this app sends the user's own content somewhere else, asked
            // for at the point of use rather than buried in Settings, and revocable
            // there. A dialog is where iOS puts a decision like this; a sentence under a
            // title on the screen would be the explanatory clutter rule 1.1 forbids.
            .alert("Send photo to Anthropic?", isPresented: $isAskingConsent) {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Allow") {
                    model.photoConsent.grant()
                    model.clearPhotoState()
                    isPicking = true
                }
            } message: {
                Text("Photos of your food are sent to Anthropic to estimate macros. "
                     + "Nothing else leaves the device.")
            }
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch model.photoState {
        case .analysing:
            Section { ProgressView().frame(maxWidth: .infinity) }
        case .keyMissing:
            Section {
                Button("Add Claude key") { showingKeyField = true }
            }
        case .notPermitted:
            Section {
                Button("Allow photos") { isAskingConsent = true }
            }
        case .offline, .unusable, .failed:
            Section {
                if let message = model.photoState.message {
                    Text(message)
                }
                Button("Try again") { isPicking = true }
            }
        case .idle:
            if found.isEmpty {
                Section {
                    Button(MealPhotoPicker.hasCamera ? "Take photo" : "Choose photo") {
                        isPicking = true
                    }
                }
            }
        }
    }

    private func row(_ food: AnalysedFood) -> some View {
        Button {
            chosen = food
        } label: {
            FoodRow(name: food.name,
                    portion: "\(Figure.grams(food.grams)) g",
                    proteinG: food.macros.proteinG)
        }
        .buttonStyle(.plain)
    }

    /// Consent first, camera second. Asking before the camera opens means the user is
    /// deciding about a photograph that does not exist yet, which is the honest order.
    private func start() {
        guard found.isEmpty, !isPicking else { return }
        guard model.photoConsent.isGranted else {
            isAskingConsent = true
            return
        }
        isPicking = true
    }
}

extension EatModel.PhotoState {
    /// The outcome, in as few words as the outcome has (rule 1.1).
    var message: String? {
        switch self {
        case .idle, .analysing, .keyMissing, .notPermitted: return nil
        case .offline: return "Offline"
        case .unusable: return "No food found"
        case .failed: return "Failed"
        }
    }
}
