import AscensionCore
import Foundation
import Observation

/// The Eat tab's state and every action that changes it.
///
/// The views hold no logic: they read `totals`, `staples` and `meals`, and call these
/// methods. That is what lets the ticket's tests cover logging, portion scaling, the
/// dietary filter and the offline and no-key paths without a single view.
@MainActor
@Observable
public final class EatModel {
    public private(set) var date: CalendarDate
    public private(set) var entries: [DiaryEntry] = []
    public private(set) var recents: [FoodItemDTO] = []
    public private(set) var searchResults: [FoodItemDTO] = []
    public private(set) var searchState: SearchState = .idle
    public private(set) var barcodeState: BarcodeState = .idle
    /// Whether there is a yesterday worth repeating. Read once per load rather than
    /// per redraw, because it costs a fetch.
    public private(set) var hasYesterday = false

    public let staples: [FoodItemDTO]
    public let targets: NutritionTargets
    /// Exposed so the settings surface can read and write the USDA key without a
    /// second route into the Keychain.
    public let keyStore: any APIKeyStore

    private let diary: any MealDiaryStore
    private let writeBack: any NutritionWriteBack
    private let search: (any FoodSearching)?
    private let barcodes: (any BarcodeLookup)?
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public enum SearchState: Equatable {
        case idle
        case searching
        case empty
        /// No USDA key. The view offers the field that fixes it; staples and manual
        /// entry are unaffected (spec §8).
        case keyMissing
        case offline
        case failed
    }

    public enum BarcodeState: Equatable {
        case idle
        case looking
        case notFound
        case offline
        case failed
    }

    public init(dependencies: EatDependencies,
                date: CalendarDate? = nil,
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.diary = dependencies.diary
        self.writeBack = dependencies.writeBack
        self.search = dependencies.search
        self.barcodes = dependencies.barcodes
        self.keyStore = dependencies.keys
        self.staples = dependencies.staples
        self.targets = dependencies.targets
        self.calendar = calendar
        self.now = now
        self.date = date ?? CalendarDate.today(now(), calendar: calendar)
    }

    // MARK: Reading

    public var totals: DayTotals { DayTotals(entries: entries, targets: targets) }

    /// The diary, grouped the way a day is eaten. Empty meals are left out: the empty
    /// state of this screen is the staples list, not four blank headers
    /// (`docs/DESIGN_RULES.md` §1.4).
    public var meals: [MealSection] {
        Dictionary(grouping: entries, by: \.meal)
            .map { MealSection(meal: $0.key, entries: $0.value.sorted(by: Self.ordered)) }
            .sorted { $0.meal.diaryOrder < $1.meal.diaryOrder }
    }

    public var hasEntries: Bool { !entries.isEmpty }

    public var isSearchAvailable: Bool { keyStore.apiKey(for: .usda) != nil }

    public func load() {
        entries = (try? diary.entries(on: date)) ?? []
        recents = (try? diary.recentFoods(limit: 8)) ?? []
        hasYesterday = date.adding(days: -1, calendar: calendar)
            .flatMap { try? diary.entries(on: $0) }?.isEmpty == false
    }

    // MARK: Logging

    /// The primary path: one tap on a staple logs its own serving (spec §F3).
    @discardableResult
    public func logStaple(_ food: FoodItemDTO) async -> DiaryEntry? {
        guard let portion = Portion(serving: food) else { return nil }
        return await log(portion)
    }

    /// Every other path arrives here, after the user has confirmed the portion — which
    /// is what stops a remote macro figure reaching Apple Health unexamined.
    @discardableResult
    public func log(_ portion: Portion, meal: MealKind? = nil) async -> DiaryEntry? {
        let instant = now()
        var entry = DiaryEntry(date: date,
                               meal: meal ?? MealKind.current(instant, calendar: calendar),
                               portion: portion,
                               loggedAt: instant)
        do {
            try diary.remember(portion.food)
            try diary.append(entry)
        } catch {
            return nil
        }
        entries.append(entry)
        entry.healthWrite = await writeToHealth(entry)
        replace(entry)
        load()
        return entry
    }

    public func delete(_ entry: DiaryEntry) {
        try? diary.delete(id: entry.id)
        entries.removeAll { $0.id == entry.id }
    }

    /// Yesterday again, for the day that is a copy of the one before it.
    public func repeatYesterday() async {
        guard let yesterday = date.adding(days: -1, calendar: calendar),
              let previous = try? diary.entries(on: yesterday), !previous.isEmpty else { return }
        for old in previous {
            let instant = now()
            var entry = DiaryEntry(date: date, meal: old.meal, foodId: old.foodId,
                                   foodName: old.foodName, grams: old.grams,
                                   macros: old.macros, loggedAt: instant)
            guard (try? diary.append(entry)) != nil else { continue }
            entries.append(entry)
            entry.healthWrite = await writeToHealth(entry)
            replace(entry)
        }
        load()
    }

    // MARK: Lookups

    public func runSearch(_ query: String) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchResults = []
            searchState = .idle
            return
        }
        guard let search else {
            searchState = .keyMissing
            return
        }
        searchState = .searching
        do {
            let found = try await search.search(term)
            searchResults = found
            searchState = found.isEmpty ? .empty : .idle
        } catch FoodLookupError.missingAPIKey {
            searchResults = []
            searchState = .keyMissing
        } catch FoodLookupError.offline {
            searchResults = []
            searchState = .offline
        } catch {
            searchResults = []
            searchState = .failed
        }
    }

    public func clearSearch() {
        searchResults = []
        searchState = .idle
    }

    public func food(barcode: String) async -> FoodItemDTO? {
        guard let barcodes else {
            barcodeState = .failed
            return nil
        }
        barcodeState = .looking
        do {
            guard let food = try await barcodes.food(barcode: barcode) else {
                barcodeState = .notFound
                return nil
            }
            barcodeState = .idle
            return food
        } catch FoodLookupError.offline {
            barcodeState = .offline
            return nil
        } catch {
            barcodeState = .failed
            return nil
        }
    }

    public func clearBarcodeState() {
        barcodeState = .idle
    }

    // MARK: Private

    private func writeToHealth(_ entry: DiaryEntry) async -> HealthWriteState {
        do {
            return try await writeBack.write(entry.nutritionSample).diaryState
        } catch {
            return .failed
        }
    }

    private func replace(_ entry: DiaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    private static func ordered(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        if lhs.loggedAt != rhs.loggedAt { return lhs.loggedAt < rhs.loggedAt }
        return lhs.foodName < rhs.foodName
    }
}

/// One meal's rows, with the figure its header carries.
public struct MealSection: Identifiable, Hashable, Sendable {
    public let meal: MealKind
    public let entries: [DiaryEntry]

    public var id: MealKind { meal }
    public var macros: Macros { Macros.total(entries.map(\.macros)) }
}
