import AscensionCore
import Foundation
import Testing

@testable import FeatureEat

@MainActor
@Suite("Logging")
struct EatModelTests {

    private let day = EatSamples.day
    private let noon = Date(timeIntervalSince1970: 1_793_620_800)

    private func model(entries: [DiaryEntry] = [],
                       writeBack: any NutritionWriteBack = RecordingWriteBack(),
                       search: (any FoodSearching)? = nil,
                       barcodes: (any BarcodeLookup)? = nil,
                       key: String? = nil,
                       store: (any MealDiaryStore)? = nil) -> EatModel {
        let dependencies = EatDependencies(
            diary: store ?? InMemoryMealDiaryStore(entries: entries),
            writeBack: writeBack,
            search: search,
            barcodes: barcodes,
            keys: EphemeralAPIKeyStore(keys: key.map { [.usda: $0] } ?? [:]))
        return EatModel(dependencies: dependencies, date: day, now: { [noon] in noon })
    }

    @Test("one tap on a staple logs its own serving and writes it to Apple Health")
    func stapleTapLogsAndWrites() async throws {
        let health = RecordingWriteBack()
        let model = model(writeBack: health)
        let omelette = try #require(Seed.stapleFoods.first)

        let entry = try #require(await model.logStaple(omelette))

        #expect(model.entries.count == 1)
        #expect(entry.grams == omelette.servingGrams)
        #expect(entry.healthWrite == .written)

        let sample = try #require(health.written.first)
        #expect(sample.id == entry.id)
        #expect(sample.proteinG == entry.macros.proteinG)
        #expect(sample.energyKcal == entry.macros.kcal)
        #expect(sample.waterMl == nil)
    }

    @Test("the staples path needs no network and no key at all")
    func staplesWorkWithNothingAttached() async throws {
        let model = model(search: nil, barcodes: nil, key: nil)

        for staple in Seed.stapleFoods {
            _ = await model.logStaple(staple)
        }

        #expect(model.entries.count == 4)
        #expect(model.totals.eaten.proteinG > 0)
        #expect(!model.isSearchAvailable)
    }

    @Test("a meal with no write-back attached is logged and says it is not in Health")
    func unavailableWriteBackIsReported() async throws {
        let model = model(writeBack: UnavailableNutritionWriteBack())
        let omelette = try #require(Seed.stapleFoods.first)
        let entry = try #require(await model.logStaple(omelette))

        #expect(entry.healthWrite == .notWritten)
    }

    @Test("a write that throws leaves the meal logged and the row marked")
    func failedWriteStillLogs() async throws {
        let failing = RecordingWriteBack(failure: FoodLookupError.offline)
        let model = model(writeBack: failing)
        let omelette = try #require(Seed.stapleFoods.first)

        let entry = try #require(await model.logStaple(omelette))

        #expect(entry.healthWrite == .failed)
        #expect(model.entries.count == 1)
    }

    @Test("the meal is guessed from the clock and the guess can be overridden")
    func mealIsGuessedFromTheHour() async throws {
        #expect(MealKind.forHour(8) == .breakfast)
        #expect(MealKind.forHour(13) == .lunch)
        #expect(MealKind.forHour(19) == .dinner)
        #expect(MealKind.forHour(2) == .snack)

        let model = model()
        let entry = try #require(
            await model.log(Portion(food: EatSamples.rice, grams: 150), meal: .dinner))
        #expect(entry.meal == .dinner)
    }

    @Test("the diary groups by meal in the order a day is eaten, totals per meal")
    func diaryGroupsByMeal() {
        let model = model(entries: EatSamples.entries())

        model.load()

        #expect(model.meals.map(\.meal) == [.breakfast, .lunch, .snack])
        let lunch = model.meals.first { $0.meal == .lunch }
        #expect(lunch?.macros.kcal.rounded() == 650)
    }

    @Test("an empty day has no meal sections to draw")
    func emptyDayHasNoSections() {
        let model = model()

        model.load()

        #expect(model.meals.isEmpty)
        #expect(!model.hasEntries)
        #expect(model.totals.proteinRemainingG == 150)
    }

    @Test("deleting a row removes it from the day")
    func deleteRemovesEntry() async throws {
        let model = model()
        let omelette = try #require(Seed.stapleFoods.first)
        let entry = try #require(await model.logStaple(omelette))

        _ = await model.delete(entry)

        #expect(model.entries.isEmpty)
    }

    @Test("repeat yesterday copies every row onto today")
    func repeatYesterdayCopiesTheDay() async throws {
        let yesterday = try #require(day.adding(days: -1))
        let store = InMemoryMealDiaryStore(entries: EatSamples.entries(on: yesterday))
        let health = RecordingWriteBack()
        let model = model(writeBack: health, store: store)

        model.load()
        #expect(model.hasYesterday)

        await model.repeatYesterday()

        #expect(model.entries.count == 3)
        #expect(model.entries.allSatisfy { $0.date == day })
        #expect(health.written.count == 3)
    }

    @Test("with nothing logged yesterday there is nothing to repeat")
    func repeatYesterdayWithNoYesterday() async {
        let model = model()

        model.load()
        await model.repeatYesterday()

        #expect(!model.hasYesterday)
        #expect(model.entries.isEmpty)
    }
}

@MainActor
@Suite("Search and barcode states")
struct EatModelLookupTests {

    private func model(search: (any FoodSearching)? = nil,
                       barcodes: (any BarcodeLookup)? = nil,
                       key: String? = nil) -> EatModel {
        EatModel(dependencies: EatDependencies(
            diary: InMemoryMealDiaryStore(),
            search: search,
            barcodes: barcodes,
            keys: EphemeralAPIKeyStore(keys: key.map { [.usda: $0] } ?? [:])))
    }

    @Test("no key means search is unavailable and nothing else is")
    func noKeyIsItsOwnState() async {
        let model = model(search: StubSearch(result: .failure(FoodLookupError.missingAPIKey)))

        await model.runSearch("chicken")

        #expect(model.searchState == .keyMissing)
        #expect(model.searchResults.isEmpty)
        #expect(!model.isSearchAvailable)
        #expect(model.staples.count == 4)
    }

    @Test("no search provider at all is the same state, not a crash")
    func noProviderIsKeyMissing() async {
        let model = model(search: nil)

        await model.runSearch("chicken")

        #expect(model.searchState == .keyMissing)
    }

    @Test("a key present makes search available")
    func keyPresent() {
        #expect(model(key: "test-key").isSearchAvailable)
    }

    @Test("offline search is its own state, distinct from a failure")
    func offlineSearch() async {
        let model = model(search: StubSearch(result: .failure(FoodLookupError.offline)),
                          key: "test-key")

        await model.runSearch("chicken")

        #expect(model.searchState == .offline)
    }

    @Test("a search with no hits is empty, not failed")
    func emptySearch() async {
        let model = model(search: StubSearch(result: .success([])), key: "test-key")

        await model.runSearch("unobtainium")

        #expect(model.searchState == .empty)
    }

    @Test("results land and clear")
    func resultsLandAndClear() async {
        let model = model(search: StubSearch(result: .success([EatSamples.chickenBreast])),
                          key: "test-key")

        await model.runSearch("chicken")
        #expect(model.searchResults.count == 1)
        #expect(model.searchState == .idle)

        model.clearSearch()
        #expect(model.searchResults.isEmpty)
        #expect(model.searchState == .idle)
    }

    @Test("an unknown barcode and an offline one are told apart")
    func barcodeStates() async {
        let unknown = model(barcodes: StubBarcodes(result: .success(nil)))
        #expect(await unknown.food(barcode: "0000000000000") == nil)
        #expect(unknown.barcodeState == .notFound)

        let offline = model(barcodes: StubBarcodes(result: .failure(FoodLookupError.offline)))
        #expect(await offline.food(barcode: "5000108501000") == nil)
        #expect(offline.barcodeState == .offline)

        let found = model(barcodes: StubBarcodes(result: .success(EatSamples.oats)))
        #expect(await found.food(barcode: "5000108501000")?.name == "Rolled oats")
        #expect(found.barcodeState == .idle)
    }
}

@Suite("API keys")
struct APIKeyStoreTests {

    @Test("a key written is a key read back")
    func roundTrip() throws {
        let store = EphemeralAPIKeyStore()
        #expect(store.apiKey(for: .usda) == nil)

        try store.setAPIKey("  test-key  ", for: .usda)
        #expect(store.apiKey(for: .usda) == "test-key")

        try store.setAPIKey(nil, for: .usda)
        #expect(store.apiKey(for: .usda) == nil)
    }

    @Test("an empty key is no key, not an empty one")
    func blankKeyClears() throws {
        let store = EphemeralAPIKeyStore(keys: [.usda: "old"])

        try store.setAPIKey("   ", for: .usda)

        #expect(store.apiKey(for: .usda) == nil)
    }

    @Test("both food sources are credited, with their licences")
    func creditsCoverBothSources() {
        let sources = EatCredits.all.map(\.source)

        #expect(sources.contains("Open Food Facts"))
        #expect(sources.contains("FoodData Central"))
        #expect(EatCredits.all.first { $0.source == "Open Food Facts" }?.licence == "ODbL 1.0")
    }
}
