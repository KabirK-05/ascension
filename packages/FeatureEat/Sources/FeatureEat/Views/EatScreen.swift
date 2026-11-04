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
/// meal's own total on its header and for swipe-to-delete and tap-to-edit on a logged
/// row, MacroFactor for the day's figures above the log, for reaching scan and search
/// from one place and for the editable logged-food detail, Cal AI for the photo
/// scan → result → confirm sequence and for confirming a portion before it is logged.
/// Patterns only.
public struct EatScreen: View {
    @State private var model: EatModel
    @State private var sheet: EatSheet?
    @State private var editing: DiaryEntry?

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
                        Task { await model.delete(entry) }
                    } edit: { entry in
                        editing = entry
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Eat")
            .toolbar { toolbar }
            .sheet(item: $sheet, content: sheetContent)
            .sheet(item: $editing, content: editor)
            .alert("Still in Apple Health",
                   isPresented: Binding(get: { model.mutationFailure == .healthUnreachable },
                                        set: { if !$0 { model.clearMutationFailure() } })) {
                Button("OK") { model.clearMutationFailure() }
            }
            .onAppear { model.load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Search", systemImage: "magnifyingglass") { sheet = .search }
                Button("Scan", systemImage: "barcode.viewfinder") { sheet = .barcode }
                if model.isPhotoAvailable {
                    Button("Photo", systemImage: "camera") { sheet = .photo }
                }
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
        case .photo:
            PhotoScanSheet(model: model)
        case .custom:
            CustomFoodSheet(model: model)
        }
    }

    /// Tapping a row opens the same editor the photo path confirms into, with the
    /// delete on it as well — the row's swipe is the quick way, this is the deliberate
    /// one (MyFitnessPal and MacroFactor both offer the pair).
    private func editor(_ entry: DiaryEntry) -> some View {
        MealEditorSheet(mode: .edit(entry), meal: entry.meal) { portion, meal in
            await model.update(entry, to: portion, meal: meal)
        } remove: {
            await model.delete(entry)
        }
    }
}

enum EatSheet: String, Identifiable {
    case search
    case barcode
    case photo
    case custom

    var id: String { rawValue }
}
