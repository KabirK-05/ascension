import AscensionCore
import Foundation
import SwiftData
import SyncClient

/// The writes a drained mutation makes, kept apart from the reads.
///
/// Each one is an upsert on the row's natural key — the single settings row, the active
/// program, a date, a date and an exercise — so applying the same mutation twice leaves the
/// store in the same state as applying it once. That is the property the drain's ledger
/// protects and this does not depend on.
@MainActor
extension LocalStore {
    /// The zone the store's own documents are keyed in.
    var timeZone: TimeZone {
        TimeZone(identifier: goals.timezone) ?? .gmt
    }

    /// There is exactly one settings row (spec §7 — a single-user app). Extra rows would
    /// make `goals` depend on fetch order, so the replacement clears whatever is there.
    func replaceGoalSettings(with document: GoalSettingsDocument) throws {
        for stale in (try? context.fetch(FetchDescriptor<GoalSettings>())) ?? [] {
            context.delete(stale)
        }
        context.insert(GoalSettings(document: document))
        try context.save()
    }

    /// Replaces the active program wholesale. `Program` cascades to its days and session
    /// templates, so patching the graph in place would mean reconciling three levels of
    /// relationship against a body that carries no ids.
    func replaceProgram(with document: ProgramDocument) throws {
        for stale in (try? context.fetch(FetchDescriptor<Program>())) ?? [] {
            context.delete(stale)
        }
        context.insert(Program(document: document, isActive: true))
        try context.save()
    }

    /// Staples are a closed, ordered list the user reaches for (spec §2), so `set_staples`
    /// replaces them rather than merging. Foods from a lookup are untouched: they carry a
    /// different `source` and the diary still points at them.
    func replaceStaples(with staples: [FoodItemDTO]) throws {
        let stored = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        for stale in stored where stale.source == .staple {
            context.delete(stale)
        }
        for food in staples {
            context.insert(FoodItem(dto: food))
        }
        try context.save()
    }

    /// One check-in per day: `CheckIn.date` is `@Attribute(.unique)`, so a second insert
    /// for the same date would fail rather than update.
    func upsertCheckIn(_ payload: MutationPayload.CheckInPayload) throws {
        try upsertCheckIn(date: payload.date, energy: payload.energy,
                          soreness: payload.soreness)
    }

    /// The same upsert from the app's own check-in, which has a `CheckInRollup` rather than
    /// a drained mutation. `CheckInPayload`'s memberwise initialiser is internal to
    /// `SyncClient`, so the shell cannot build one — the same reason `insertMeal` carries
    /// two overloads.
    func upsertCheckIn(date: CalendarDate, energy: Int, soreness: Soreness) throws {
        let day = date.rawValue
        let existing = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.date == day })
        for stale in (try? context.fetch(existing)) ?? [] {
            context.delete(stale)
        }
        context.insert(CheckIn(date: date, energy: energy, soreness: soreness))
        try context.save()
    }

    /// One `MealLog` row per item in the meal, which is how the diary and `meals.csv` both
    /// read a plate: the portion is the row, not the plate.
    ///
    /// `MealLog` carries no row id (spec §7), so a re-applied `log_meal` cannot be matched
    /// by its mutation id and would total twice. The drain's persisted applied-id ledger is
    /// what prevents that, and it is the reason `FileSyncStateStore` writes the ledger
    /// atomically beside the cursor rather than holding it in memory.
    func insertMeal(_ payload: MutationPayload.LoggedMealPayload) throws {
        for item in payload.items {
            let food = item.foodItemId.flatMap { storedFood(id: $0) }
            context.insert(MealLog(
                date: payload.date,
                meal: payload.meal,
                grams: item.grams,
                macros: Macros(kcal: item.kcal, proteinG: item.proteinG,
                               fatG: item.fatG, carbsG: item.carbsG),
                foodItem: food,
                foodName: item.name))
        }
        try context.save()
    }

    /// Inserts one logged portion of a stored food.
    ///
    /// The App Intents path, which has no mutation behind it and therefore no
    /// `MutationPayload.LoggedMealPayload` to build — those types carry no public
    /// memberwise initialiser, and adding one would mean editing `SyncClient` to save a
    /// line here.
    func insertMeal(date: CalendarDate, meal: MealKind, food: FoodItemDTO,
                    grams: Double, macros: Macros) throws {
        context.insert(MealLog(date: date, meal: meal, grams: grams, macros: macros,
                               foodItem: storedFood(id: food.id), foodName: food.name))
        try context.save()
    }

    func storedFood(id: String) -> FoodItem? {
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
