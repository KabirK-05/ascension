import AscensionCore
import DesignSystem
import SwiftUI

/// Eat (spec §F3). Answers one question: how much protein is left?
///
/// The order is the order of use. The ring answers the question; the staples are the
/// primary logging path and sit directly under it, one tap each; the diary is the
/// record and comes last. An empty diary shows staples and nothing else — the empty
/// state is a control, not a paragraph (`docs/DESIGN_RULES.md` §1.4).
///
/// Mobbin references: MyFitnessPal and Cronometer for the meal-grouped diary with the
/// meal's own total on its header, MacroFactor for the day's figures above the log and
/// for reaching scan and search from one place, Cal AI for confirming a portion before
/// it is logged. Patterns only.
public struct EatScreen: View {
    @State private var model: EatModel
    @State private var sheet: EatSheet?

    /// The shell's entry point. Resolves the app's own store; see `EatDependencies`.
    public init() {
        _model = State(initialValue: EatModel(dependencies: .resolved()))
    }

    public init(dependencies: EatDependencies) {
        _model = State(initialValue: EatModel(dependencies: dependencies))
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TotalsHeader(totals: model.totals)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                StaplesSection(staples: model.staples) { staple in
                    Task { await model.logStaple(staple) }
                }

                ForEach(model.meals) { section in
                    DiarySection(section: section) { entry in
                        model.delete(entry)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Eat")
            .toolbar { toolbar }
            .sheet(item: $sheet, content: sheetContent)
            .onAppear { model.load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Search", systemImage: "magnifyingglass") { sheet = .search }
                Button("Scan", systemImage: "barcode.viewfinder") { sheet = .barcode }
                Button("Custom", systemImage: "square.and.pencil") { sheet = .custom }
                if model.hasYesterday {
                    Button("Repeat yesterday", systemImage: "arrow.clockwise") {
                        Task { await model.repeatYesterday() }
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: EatSheet) -> some View {
        switch sheet {
        case .search:
            AddFoodSheet(model: model)
        case .barcode:
            BarcodeSheet(model: model)
        case .custom:
            CustomFoodSheet(model: model)
        }
    }
}

enum EatSheet: String, Identifiable {
    case search
    case barcode
    case custom

    var id: String { rawValue }
}
