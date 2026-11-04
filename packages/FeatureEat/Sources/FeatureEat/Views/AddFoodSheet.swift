import AscensionCore
import DesignSystem
import SwiftUI

/// Search and recents, the two paths that are not a staple.
///
/// Recents come first and need no network: the Lifesum and MyFitnessPal arrangement,
/// where what you ate before is one tap and the database is the fallback. Search is
/// USDA (spec §10) and needs the user's own key — without one the section is a button
/// that fixes it, not a paragraph explaining the problem.
struct AddFoodSheet: View {
    let model: EatModel

    @State private var query = ""
    @State private var chosen: FoodItemDTO?
    @State private var showingKeyField = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.recents.isEmpty, query.isEmpty {
                    Section("Recents") {
                        ForEach(model.recents) { food in
                            row(food)
                        }
                    }
                }
                resultsSection
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Food")
            .onSubmit(of: .search) { Task { await model.runSearch(query) } }
            .onChange(of: query) { _, new in
                if new.isEmpty { model.clearSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $chosen) { food in
                PortionSheet(food: food, meal: MealKind.current(Date())) { portion, meal in
                    await model.log(portion, meal: meal)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingKeyField) {
                FoodDataSettingsView(keys: model.keyStore)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch model.searchState {
        case .searching:
            Section { ProgressView().frame(maxWidth: .infinity) }
        case .keyMissing:
            Section {
                Button("Add USDA key") { showingKeyField = true }
            }
        case .offline, .failed:
            Section {
                Button("Try again") { Task { await model.runSearch(query) } }
            }
        case .idle, .empty:
            if !model.searchResults.isEmpty {
                Section("Results") {
                    ForEach(model.searchResults) { food in
                        row(food)
                    }
                }
            }
        }
    }

    private func row(_ food: FoodItemDTO) -> some View {
        Button {
            chosen = food
        } label: {
            FoodRow(name: food.name,
                    portion: food.servingName ?? "100 g",
                    proteinG: food.servingMacros?.proteinG ?? food.proteinPer100g)
        }
        .buttonStyle(.plain)
    }
}
