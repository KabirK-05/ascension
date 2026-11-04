import AscensionCore
import Foundation
import SwiftData
import Testing

@testable import FeatureEat

/// The fix underneath ASC-24's delete.
///
/// A row's id is the key Apple Health holds its samples under. Before this ticket the
/// `SwiftDataMealDiaryStore` minted ids per launch, so a meal logged yesterday had a new
/// id today and its samples could no longer be found: deleting it emptied the diary and
/// left the calories in Health. These tests are the ones that would have caught that.
@Suite("Diary row identity")
@MainActor
struct DiaryIdentityTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: AscensionSchema.schema,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func entry(_ name: String = "Chicken breast", grams: Double = 200,
                       at hour: Int = 13) -> DiaryEntry {
        let start = EatSamples.day.date() ?? Date()
        return DiaryEntry(date: EatSamples.day, meal: .lunch, foodName: name, grams: grams,
                          macros: Macros(kcal: 330, proteinG: 62, fatG: 7.2, carbsG: 0),
                          loggedAt: start.addingTimeInterval(Double(hour) * 3600),
                          healthWrite: .written)
    }

    @Test("a row keeps its id across a relaunch, so Apple Health can still be reached")
    func idSurvivesARelaunch() throws {
        let container = try container()
        let identity = MemoryDiaryIdentityStore()
        let logged = entry()

        let first = SwiftDataMealDiaryStore(context: ModelContext(container),
                                            identity: identity)
        try first.append(logged)

        // A second store over the same persistent data and the same identity file is
        // what the next launch is.
        let second = SwiftDataMealDiaryStore(context: ModelContext(container),
                                             identity: identity)
        let rows = try second.entries(on: EatSamples.day)
        #expect(rows.count == 1)
        #expect(rows.first?.id == logged.id)
    }

    @Test("the time of day survives too, so the diary keeps its order")
    func loggedAtSurvivesARelaunch() throws {
        let container = try container()
        let identity = MemoryDiaryIdentityStore()
        let early = entry("Omelette", grams: 300, at: 9)
        let late = entry("Rice", grams: 250, at: 19)

        let first = SwiftDataMealDiaryStore(context: ModelContext(container),
                                            identity: identity)
        try first.append(late)
        try first.append(early)

        let second = SwiftDataMealDiaryStore(context: ModelContext(container),
                                             identity: identity)
        let rows = try second.entries(on: EatSamples.day).sorted { $0.loggedAt < $1.loggedAt }
        #expect(rows.map(\.foodName) == ["Omelette", "Rice"])
    }

    @Test("so does whether the row reached Apple Health")
    func healthStateSurvivesARelaunch() throws {
        let container = try container()
        let identity = MemoryDiaryIdentityStore()
        let logged = entry()

        let first = SwiftDataMealDiaryStore(context: ModelContext(container),
                                            identity: identity)
        try first.append(logged)
        try first.recordHealthWrite(.written, for: logged.id)

        let second = SwiftDataMealDiaryStore(context: ModelContext(container),
                                             identity: identity)
        #expect(try second.entries(on: EatSamples.day).first?.healthWrite == .written)
    }

    @Test("a row logged in an earlier session still deletes")
    func deleteWorksAfterARelaunch() throws {
        let container = try container()
        let identity = MemoryDiaryIdentityStore()
        let logged = entry()

        let first = SwiftDataMealDiaryStore(context: ModelContext(container),
                                            identity: identity)
        try first.append(logged)

        let second = SwiftDataMealDiaryStore(context: ModelContext(container),
                                             identity: identity)
        try second.delete(id: logged.id)
        #expect(try second.entries(on: EatSamples.day).isEmpty)
    }

    @Test("an edit rewrites the row and keeps its id")
    func updateKeepsTheId() throws {
        let container = try container()
        let store = SwiftDataMealDiaryStore(context: ModelContext(container),
                                            identity: MemoryDiaryIdentityStore())
        let logged = entry()
        try store.append(logged)

        var edited = logged
        edited = DiaryEntry(id: logged.id, date: logged.date, meal: .dinner,
                            foodName: "Chicken breast", grams: 100,
                            macros: Macros(kcal: 165, proteinG: 31, fatG: 3.6, carbsG: 0),
                            loggedAt: logged.loggedAt)
        try store.update(edited)

        let rows = try store.entries(on: EatSamples.day)
        #expect(rows.count == 1)
        #expect(rows.first?.id == logged.id)
        #expect(rows.first?.grams == 100)
        #expect(rows.first?.meal == .dinner)
    }

    @Test("editing a row the store has never seen is refused, not silently ignored")
    func updateRefusesAnUnknownRow() throws {
        let container = try container()
        let store = SwiftDataMealDiaryStore(context: ModelContext(container),
                                            identity: MemoryDiaryIdentityStore())

        #expect(throws: DiaryStoreError.rowNotFound) {
            try store.update(entry())
        }
    }

    @Test("a row written before this ticket gets an id now and keeps it")
    func adoptsRowsWithNoRecordedIdentity() throws {
        let container = try container()
        let context = ModelContext(container)
        context.insert(MealLog(date: EatSamples.day, meal: .lunch, grams: 200,
                               macros: Macros(kcal: 330, proteinG: 62, fatG: 7.2, carbsG: 0),
                               foodName: "Chicken breast"))
        try context.save()

        let identity = MemoryDiaryIdentityStore()
        let store = SwiftDataMealDiaryStore(context: context, identity: identity)
        let adopted = try #require(try store.entries(on: EatSamples.day).first)

        let next = SwiftDataMealDiaryStore(context: ModelContext(container),
                                           identity: identity)
        #expect(try next.entries(on: EatSamples.day).first?.id == adopted.id)
    }

    @Test("the identity file round-trips, which is the whole mechanism")
    func recordsEncodeAndDecode() throws {
        let container = try container()
        let context = ModelContext(container)
        let log = MealLog(date: EatSamples.day, meal: .lunch, grams: 200,
                          macros: Macros(kcal: 330, proteinG: 62, fatG: 7.2, carbsG: 0),
                          foodName: "Chicken breast")
        context.insert(log)
        try context.save()

        let record = DiaryIdentityRecord(model: log.persistentModelID,
                                         loggedAt: Date(timeIntervalSince1970: 1_762_000_000),
                                         healthWrite: .partial)
        let data = try JSONEncoder().encode(["row-1": record])
        let decoded = try JSONDecoder().decode([String: DiaryIdentityRecord].self, from: data)

        #expect(decoded["row-1"] == record)
        #expect(context.model(for: try #require(decoded["row-1"]).model) as? MealLog === log)
    }

    @Test("a record written before the Health field existed still loads")
    func decodesRecordsWithoutTheHealthField() throws {
        let container = try container()
        let context = ModelContext(container)
        let log = MealLog(date: EatSamples.day, meal: .lunch, grams: 200,
                          macros: Macros(kcal: 330, proteinG: 62, fatG: 7.2, carbsG: 0),
                          foodName: "Chicken breast")
        context.insert(log)
        try context.save()

        // Encode a record, then strip the field a pre-ASC-24 file would not have had.
        let full = try JSONEncoder().encode(
            DiaryIdentityRecord(model: log.persistentModelID, loggedAt: Date(),
                                healthWrite: .written))
        var object = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        object["healthWrite"] = nil
        let trimmed = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DiaryIdentityRecord.self, from: trimmed)
        #expect(decoded.healthWrite == .notWritten)
    }

    @Test("the file store writes and reads back what it was given")
    func fileStoreRoundTrips() throws {
        let container = try container()
        let context = ModelContext(container)
        let log = MealLog(date: EatSamples.day, meal: .lunch, grams: 200,
                          macros: Macros(kcal: 330, proteinG: 62, fatG: 7.2, carbsG: 0),
                          foodName: "Chicken breast")
        context.insert(log)
        try context.save()

        let url = URL.temporaryDirectory.appending(path: "identity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let record = DiaryIdentityRecord(model: log.persistentModelID, loggedAt: Date(),
                                         healthWrite: .written)

        FileDiaryIdentityStore(url: url).save(["row-1": record])
        #expect(FileDiaryIdentityStore(url: url).load()["row-1"] == record)
    }
}
