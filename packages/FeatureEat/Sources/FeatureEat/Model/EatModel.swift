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
    public private(set) var photoState: PhotoState = .idle
    /// The last delete or edit that did not complete. Set rather than thrown so the
    /// screen can say so: a row that is still in Apple Health must not quietly vanish
    /// from the diary (ASC-24).
    public private(set) var mutationFailure: MutationFailure?
    /// Whether there is a yesterday worth repeating. Read once per load rather than
    /// per redraw, because it costs a fetch.
    public private(set) var hasYesterday = false

    public let staples: [FoodItemDTO]
    public let targets: NutritionTargets
    /// Exposed so the settings surface can read and write the USDA key without a
    /// second route into the Keychain.
    public let keyStore: any APIKeyStore
    public let photoConsent: any MealPhotoConsenting

    private let diary: any MealDiaryStore
    private let writeBack: any NutritionWriteBack
    private let search: (any FoodSearching)?
    private let barcodes: (any BarcodeLookup)?
    private let photos: (any MealPhotoAnalysing)?
    private let diaryDidChange: @Sendable () async -> Void
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

    public enum PhotoState: Equatable {
        case idle
        case analysing
        /// No Claude key. The photo path alone is unavailable; every other path on this
        /// tab is untouched, which is the point of it being an addition.
        case keyMissing
        /// The user has not agreed to send a photograph off the device, or has revoked it.
        case notPermitted
        case offline
        /// Answered, but with nothing worth showing: unreadable, empty, or everything in
        /// it failed the dietary rule.
        case unusable
        case failed
    }

    /// Why a delete or an edit stopped. One case, because the user's next move is the
    /// same either way and a taxonomy would be clutter: the row is still there.
    public enum MutationFailure: Equatable {
        /// Apple Health could not be reached, so the row was left where it is rather
        /// than letting the diary and Health drift apart.
        case healthUnreachable
        /// The diary itself refused the change.
        case storeFailed
    }

    public init(dependencies: EatDependencies,
                date: CalendarDate? = nil,
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.diary = dependencies.diary
        self.writeBack = dependencies.writeBack
        self.search = dependencies.search
        self.barcodes = dependencies.barcodes
        self.photos = dependencies.photos
        self.photoConsent = dependencies.photoConsent
        self.diaryDidChange = dependencies.diaryDidChange
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

    /// Whether the menu offers the camera at all. A key the user has not added is the
    /// one case worth offering anyway — the sheet is where they add it.
    public var isPhotoAvailable: Bool { photos != nil }

    /// Re-reads the day from the store.
    ///
    /// The store is the owner of a row's Apple Health state, not this model (ASC-24).
    /// Before that, every `load()` reset each row to "not in Apple Health" — a wrong
    /// marker on every row, and worse, a `delete` that then believed it had nothing to
    /// take back out of Health.
    public func load() {
        entries = (try? diary.entries(on: date)) ?? []
        recents = (try? diary.recentFoods(limit: 8)) ?? []
        hasYesterday = date.adding(days: -1, calendar: calendar)
            .flatMap { try? diary.entries(on: $0) }?.isEmpty == false
    }

    public func clearMutationFailure() {
        mutationFailure = nil
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
            mutationFailure = .storeFailed
            return nil
        }
        entries.append(entry)
        entry.healthWrite = await writeToHealth(entry)
        load()
        await diaryDidChange()
        return entry
    }

    /// Removes a row from the diary **and** from Apple Health.
    ///
    /// Health first, diary second, and that order is the fix. Before ASC-24 this method
    /// deleted the local row only, so a meal entered by accident left its calories,
    /// protein, carbohydrate and fat in Apple Health with nothing left pointing at them.
    /// Doing Health first means a removal that fails leaves both halves intact and
    /// says so, rather than producing the one state that cannot be repaired from the
    /// screen: a diary with no row and a Health day that still counts it.
    ///
    /// A row that never reached Health has nothing to remove and goes straight through,
    /// which is also what keeps the tab working with no write-back injected at all.
    @discardableResult
    public func delete(_ entry: DiaryEntry) async -> Bool {
        mutationFailure = nil
        guard await removeFromHealth(entry) else {
            mutationFailure = .healthUnreachable
            return false
        }
        do {
            try diary.delete(id: entry.id)
        } catch {
            mutationFailure = .storeFailed
            // Health no longer holds it, so the row must not keep claiming it does.
            markAndRecord(entry.id, as: .notWritten)
            return false
        }
        entries.removeAll { $0.id == entry.id }
        load()
        await diaryDidChange()
        return true
    }

    /// Changes a logged row's portion, macros or meal, keeping its id.
    ///
    /// In HealthKit terms an edit is a delete plus a write. `HealthWriter` replaces a
    /// sample carrying the same sync identifier *when the sync version is higher*, and
    /// `NutritionSample` carries no version — so re-saving alone could leave the old
    /// figures standing. Removing first is the one shape that is correct either way, and
    /// it reuses the delete path this ticket had to build regardless.
    @discardableResult
    public func update(_ entry: DiaryEntry, to portion: Portion,
                       meal: MealKind? = nil) async -> Bool {
        mutationFailure = nil
        let edited = DiaryEntry(id: entry.id, date: entry.date, meal: meal ?? entry.meal,
                                portion: portion, loggedAt: entry.loggedAt)
        guard await removeFromHealth(entry) else {
            mutationFailure = .healthUnreachable
            return false
        }
        do {
            try diary.remember(portion.food)
            try diary.update(edited)
        } catch {
            mutationFailure = .storeFailed
            markAndRecord(entry.id, as: .notWritten)
            return false
        }
        await writeToHealth(edited)
        load()
        await diaryDidChange()
        return true
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
        }
        load()
        await diaryDidChange()
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

    /// A photograph of a plate, estimated. Nothing is logged here — the caller takes the
    /// result to the editor, and only a portion the user has accepted reaches the diary.
    public func foods(inPhoto jpeg: Data) async -> [AnalysedFood] {
        guard let photos else {
            photoState = .failed
            return []
        }
        photoState = .analysing
        do {
            let found = try await photos.foods(inPhoto: jpeg)
            photoState = found.isEmpty ? .unusable : .idle
            return found
        } catch MealAnalysisError.missingAPIKey {
            photoState = .keyMissing
        } catch MealAnalysisError.notPermitted {
            photoState = .notPermitted
        } catch MealAnalysisError.offline {
            photoState = .offline
        } catch MealAnalysisError.unusableResponse {
            photoState = .unusable
        } catch {
            photoState = .failed
        }
        return []
    }

    public func clearPhotoState() {
        photoState = .idle
    }

    // MARK: Private

    /// Writes the entry to Apple Health and records the outcome where it survives a
    /// relaunch, because that outcome is what a later delete reads.
    @discardableResult
    private func writeToHealth(_ entry: DiaryEntry) async -> HealthWriteState {
        let state: HealthWriteState
        do {
            state = try await writeBack.write(entry.nutritionSample).diaryState
        } catch {
            state = .failed
        }
        try? diary.recordHealthWrite(state, for: entry.id)
        mark(entry.id, as: state)
        return state
    }

    /// Whether Apple Health is, after this, free of the samples for `entry`.
    ///
    /// `partial` counts as success for the same reason it does on a write: HealthKit
    /// authorisation is per type, so a scope the user refused never received a sample
    /// and has nothing of ours left in it.
    private func removeFromHealth(_ entry: DiaryEntry) async -> Bool {
        switch entry.healthWrite {
        case .notWritten:
            // Never landed. Nothing to take back, and no reason to let an unavailable
            // write-back block the delete.
            return true
        case .written, .partial, .failed:
            do {
                switch try await writeBack.remove(sampleId: entry.id) {
                case .removed, .partial: return true
                case .unavailable: return false
                }
            } catch {
                return false
            }
        }
    }

    private func mark(_ id: String, as state: HealthWriteState) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].healthWrite = state
    }

    /// Records a state the store has to keep as well as the screen — used where Apple
    /// Health and the diary have come apart and the row must stop claiming otherwise.
    private func markAndRecord(_ id: String, as state: HealthWriteState) {
        mark(id, as: state)
        try? diary.recordHealthWrite(state, for: id)
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
