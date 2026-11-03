import AscensionCore
import Foundation
import SwiftData

/// The diary, in the app's own store.
///
/// `MealLog` (spec §7) carries the day, the meal, the portion and the macros, and
/// nothing else: no row id and no time of day. Both are needed on screen — a row has
/// to be deletable, and rows within a meal have to hold an order — so this store keeps
/// them beside the model rather than adding fields to another ticket's package. The
/// consequence is deliberate and small: ids live for as long as the process, so a
/// relaunch renumbers them, and rows logged in an earlier session sort by name.
@MainActor
public final class SwiftDataMealDiaryStore: MealDiaryStore {
    private let context: ModelContext
    private var identifiers: [String: PersistentIdentifier] = [:]
    private var loggedAt: [String: Date] = [:]

    public init(context: ModelContext) {
        self.context = context
    }

    public func entries(on date: CalendarDate) throws -> [DiaryEntry] {
        let day = date.rawValue
        let descriptor = FetchDescriptor<MealLog>(predicate: #Predicate { $0.date == day })
        return try context.fetch(descriptor).map { entry(for: $0, on: date) }
    }

    public func append(_ entry: DiaryEntry) throws {
        let food = try entry.foodId.flatMap { try storedFood(id: $0) }
        let log = MealLog(date: entry.date, meal: entry.meal, grams: entry.grams,
                          macros: entry.macros, foodItem: food, foodName: entry.foodName)
        context.insert(log)
        try context.save()
        identifiers[entry.id] = log.persistentModelID
        loggedAt[entry.id] = entry.loggedAt
    }

    public func delete(id: String) throws {
        guard let identifier = identifiers[id],
              let log = context.model(for: identifier) as? MealLog else { return }
        context.delete(log)
        try context.save()
        identifiers[id] = nil
        loggedAt[id] = nil
    }

    /// Foods eaten before, newest day first. Read back out of the diary rather than
    /// kept as its own list, so "recent" means recently eaten and cannot drift.
    public func recentFoods(limit: Int) throws -> [FoodItemDTO] {
        var descriptor = FetchDescriptor<MealLog>(
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = max(limit, 1) * 8
        var seen: Set<String> = []
        var foods: [FoodItemDTO] = []
        for log in try context.fetch(descriptor) {
            guard let food = log.foodItem, food.source != .staple,
                  seen.insert(food.id).inserted else { continue }
            foods.append(food.dto)
            if foods.count == limit { break }
        }
        return foods
    }

    /// Keeps a looked-up food so a later tap can log it without the network.
    public func remember(_ food: FoodItemDTO) throws {
        if try storedFood(id: food.id) == nil {
            context.insert(FoodItem(dto: food))
            try context.save()
        }
    }

    private func entry(for log: MealLog, on date: CalendarDate) -> DiaryEntry {
        let id = identifiers.first { $0.value == log.persistentModelID }?.key
            ?? register(log)
        return DiaryEntry(id: id, date: date, meal: log.meal, foodId: log.foodItem?.id,
                          foodName: log.foodName, grams: log.grams, macros: log.macros,
                          loggedAt: loggedAt[id] ?? date.date() ?? Date())
    }

    private func register(_ log: MealLog) -> String {
        let id = UUID().uuidString
        identifiers[id] = log.persistentModelID
        return id
    }

    private func storedFood(id: String) throws -> FoodItem? {
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

}
