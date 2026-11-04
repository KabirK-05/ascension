import AscensionCore
import Foundation
import SwiftData

/// The diary, in the app's own store.
///
/// `MealLog` (spec §7) carries the day, the meal, the portion and the macros, and
/// nothing else: no row id and no time of day. Both are needed on screen — a row has to
/// be deletable and editable, and rows within a meal have to hold an order — so this
/// store keeps them beside the model rather than adding fields to another ticket's
/// package.
///
/// Those two facts used to live in dictionaries that died with the process. ASC-24 made
/// that a bug rather than a wrinkle: a row's id becomes the HealthKit sync identifier, so
/// a renumbered id means yesterday's meal can be removed from the diary but never from
/// Apple Health. `DiaryIdentityStore` persists the mapping, and this store reads and
/// repairs it on every fetch.
@MainActor
public final class SwiftDataMealDiaryStore: MealDiaryStore {
    private let context: ModelContext
    private let identity: any DiaryIdentityStore
    private var records: [String: DiaryIdentityRecord]

    public convenience init(context: ModelContext) {
        self.init(context: context, identity: FileDiaryIdentityStore())
    }

    init(context: ModelContext, identity: any DiaryIdentityStore) {
        self.context = context
        self.identity = identity
        self.records = identity.load()
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
        // Saved before the identifier is read: SwiftData hands out a temporary identifier
        // for an unsaved model and swaps it for the permanent one on save, and the
        // temporary one would not survive a relaunch.
        try context.save()
        write(entry.id, DiaryIdentityRecord(model: log.persistentModelID,
                                            loggedAt: entry.loggedAt,
                                            healthWrite: entry.healthWrite))
    }

    /// Rewrites the row behind `entry.id` — portion, macros, meal and name.
    ///
    /// The `MealLog` object is reused rather than deleted and reinserted, so the row keeps
    /// its persistent identifier and the id the caller already handed to Apple Health
    /// stays pointing at it.
    public func update(_ entry: DiaryEntry) throws {
        guard let log = log(for: entry.id) else { throw DiaryStoreError.rowNotFound }
        log.meal = entry.meal
        log.grams = entry.grams
        log.kcal = entry.macros.kcal
        log.proteinG = entry.macros.proteinG
        log.fatG = entry.macros.fatG
        log.carbsG = entry.macros.carbsG
        log.foodName = entry.foodName
        if let foodId = entry.foodId {
            log.foodItem = try storedFood(id: foodId)
        }
        try context.save()
        write(entry.id, DiaryIdentityRecord(model: log.persistentModelID,
                                            loggedAt: entry.loggedAt,
                                            healthWrite: entry.healthWrite))
    }

    public func recordHealthWrite(_ state: HealthWriteState, for id: String) throws {
        guard var record = records[id] else { return }
        record.healthWrite = state
        write(id, record)
    }

    public func delete(id: String) throws {
        guard let log = log(for: id) else {
            // Already gone — the state the caller asked for. Drop the mapping so the file
            // does not accumulate records for rows that no longer exist.
            write(id, nil)
            return
        }
        context.delete(log)
        try context.save()
        write(id, nil)
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

    // MARK: - Identity

    private func entry(for log: MealLog, on date: CalendarDate) -> DiaryEntry {
        let identifier = log.persistentModelID
        let known = records.first { $0.value.model == identifier }
        let id = known?.key ?? register(log)
        let record = records[id]
        return DiaryEntry(id: id, date: date, meal: log.meal, foodId: log.foodItem?.id,
                          foodName: log.foodName, grams: log.grams, macros: log.macros,
                          loggedAt: record?.loggedAt ?? date.date() ?? Date(),
                          healthWrite: record?.healthWrite ?? .notWritten)
    }

    /// A row this store has never seen — written before ASC-24, or by another surface.
    /// It gets an id now, and keeps it from here on.
    private func register(_ log: MealLog) -> String {
        let id = UUID().uuidString
        let day = CalendarDate(rawValue: log.date)?.date() ?? Date()
        write(id, DiaryIdentityRecord(model: log.persistentModelID, loggedAt: day))
        return id
    }

    private func log(for id: String) -> MealLog? {
        guard let record = records[id] else { return nil }
        return context.model(for: record.model) as? MealLog
    }

    private func write(_ id: String, _ record: DiaryIdentityRecord?) {
        records[id] = record
        identity.save(records)
    }

    private func storedFood(id: String) throws -> FoodItem? {
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }
}

public enum DiaryStoreError: Error, Equatable {
    /// The row the caller named is not in the diary. Thrown rather than ignored: an edit
    /// that silently does nothing would leave Apple Health holding the new figures and
    /// the diary the old ones.
    case rowNotFound
}
