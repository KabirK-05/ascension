import AscensionCore
import Foundation
import SwiftData

/// Where the day's diary lives.
///
/// Behind a protocol so the screen's logic is testable without a store and previews
/// render without a container; `SwiftDataMealDiaryStore` is the one that persists.
@MainActor
public protocol MealDiaryStore: AnyObject {
    func entries(on date: CalendarDate) throws -> [DiaryEntry]
    func append(_ entry: DiaryEntry) throws
    /// Rewrites a row in place, keeping its id. The id is what Apple Health keys the
    /// meal's samples on, so an edit that minted a fresh one would orphan them.
    func update(_ entry: DiaryEntry) throws
    func delete(id: String) throws
    /// Remembers where a row stands with Apple Health, so the next launch knows whether
    /// a delete has samples to take back (ASC-24).
    func recordHealthWrite(_ state: HealthWriteState, for id: String) throws
    /// Foods logged recently, most recent first, deduplicated by food.
    func recentFoods(limit: Int) throws -> [FoodItemDTO]
    func remember(_ food: FoodItemDTO) throws
}

/// An in-memory diary, for previews and tests.
@MainActor
public final class InMemoryMealDiaryStore: MealDiaryStore {
    private var entries: [DiaryEntry]
    private var foods: [FoodItemDTO]

    public init(entries: [DiaryEntry] = [], foods: [FoodItemDTO] = []) {
        self.entries = entries
        self.foods = foods
    }

    public func entries(on date: CalendarDate) throws -> [DiaryEntry] {
        entries.filter { $0.date == date }
    }

    public func append(_ entry: DiaryEntry) throws {
        entries.append(entry)
    }

    public func update(_ entry: DiaryEntry) throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    public func delete(id: String) throws {
        entries.removeAll { $0.id == id }
    }

    public func recordHealthWrite(_ state: HealthWriteState, for id: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].healthWrite = state
    }

    public func recentFoods(limit: Int) throws -> [FoodItemDTO] {
        Array(foods.prefix(limit))
    }

    public func remember(_ food: FoodItemDTO) throws {
        foods.removeAll { $0.id == food.id }
        foods.insert(food, at: 0)
    }
}
