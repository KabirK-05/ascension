import AscensionCore
import Foundation

@testable import FeatureEat

/// An HTTP fetcher that answers from a script instead of the network.
struct StubHTTP: HTTPFetching {
    enum Answer {
        case body(String, status: Int)
        case failure(any Error)
    }

    let answer: Answer
    let record: (@Sendable (URLRequest) -> Void)?

    init(_ answer: Answer, record: (@Sendable (URLRequest) -> Void)? = nil) {
        self.answer = answer
        self.record = record
    }

    static func json(_ body: String, status: Int = 200,
                     record: (@Sendable (URLRequest) -> Void)? = nil) -> StubHTTP {
        StubHTTP(.body(body, status: status), record: record)
    }

    static let offline = StubHTTP(.failure(FoodLookupError.offline))

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record?(request)
        switch answer {
        case let .failure(error):
            throw error
        case let .body(body, status):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status,
                                                 httpVersion: nil, headerFields: nil) else {
                throw FoodLookupError.unusableResponse
            }
            return (Data(body.utf8), response)
        }
    }
}

/// A cache with no file behind it.
actor MemoryFoodCache: FoodCache {
    private var barcodes: [String: FoodItemDTO] = [:]
    private var searches: [String: [FoodItemDTO]] = [:]

    func food(forBarcode barcode: String) -> FoodItemDTO? { barcodes[barcode] }

    func store(_ food: FoodItemDTO, forBarcode barcode: String) {
        barcodes[barcode] = food
    }

    func foods(forSearch term: String) -> [FoodItemDTO] { searches[term.lowercased()] ?? [] }

    func store(_ foods: [FoodItemDTO], forSearch term: String) {
        searches[term.lowercased()] = foods
    }
}

/// Records what the Eat tab would have written to, and removed from, Apple Health.
final class RecordingWriteBack: NutritionWriteBack, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [NutritionSample] = []
    private var removals: [String] = []
    private let outcome: NutritionWriteOutcome
    private let removal: NutritionRemovalOutcome
    private let failure: (any Error)?
    private let removalFailure: (any Error)?

    init(outcome: NutritionWriteOutcome = .written,
         removal: NutritionRemovalOutcome = .removed,
         failure: (any Error)? = nil,
         removalFailure: (any Error)? = nil) {
        self.outcome = outcome
        self.removal = removal
        self.failure = failure
        self.removalFailure = removalFailure
    }

    var written: [NutritionSample] { lock.withLock { samples } }
    var removed: [String] { lock.withLock { removals } }

    func write(_ sample: NutritionSample) async throws -> NutritionWriteOutcome {
        if let failure { throw failure }
        lock.withLock { samples.append(sample) }
        return outcome
    }

    func remove(sampleId: String) async throws -> NutritionRemovalOutcome {
        if let removalFailure { throw removalFailure }
        lock.withLock { removals.append(sampleId) }
        return removal
    }
}

/// A write-back that only knows how to add — the shape of every conformer written
/// before ASC-24, used to prove the default `remove` keeps them compiling and honest.
struct AddOnlyWriteBack: NutritionWriteBack {
    func write(_ sample: NutritionSample) async throws -> NutritionWriteOutcome { .written }
}

/// A photo analyser that answers from a script.
struct StubPhotoAnalysis: MealPhotoAnalysing {
    let result: Result<[AnalysedFood], any Error>

    func foods(inPhoto jpeg: Data) async throws -> [AnalysedFood] {
        try result.get()
    }
}

/// A diary store that fails on demand, for the paths where the store is the thing that
/// breaks rather than Apple Health.
@MainActor
final class BrittleDiaryStore: MealDiaryStore {
    private let inner: InMemoryMealDiaryStore
    var failsDelete = false
    var failsUpdate = false

    init(entries: [DiaryEntry] = []) {
        inner = InMemoryMealDiaryStore(entries: entries)
    }

    func entries(on date: CalendarDate) throws -> [DiaryEntry] { try inner.entries(on: date) }
    func append(_ entry: DiaryEntry) throws { try inner.append(entry) }

    func update(_ entry: DiaryEntry) throws {
        if failsUpdate { throw DiaryStoreError.rowNotFound }
        try inner.update(entry)
    }

    func delete(id: String) throws {
        if failsDelete { throw DiaryStoreError.rowNotFound }
        try inner.delete(id: id)
    }

    func recordHealthWrite(_ state: HealthWriteState, for id: String) throws {
        try inner.recordHealthWrite(state, for: id)
    }

    func recentFoods(limit: Int) throws -> [FoodItemDTO] { try inner.recentFoods(limit: limit) }
    func remember(_ food: FoodItemDTO) throws { try inner.remember(food) }
}

struct StubSearch: FoodSearching {
    let result: Result<[FoodItemDTO], any Error>

    func search(_ query: String) async throws -> [FoodItemDTO] {
        try result.get()
    }
}

struct StubBarcodes: BarcodeLookup {
    let result: Result<FoodItemDTO?, any Error>

    func food(barcode: String) async throws -> FoodItemDTO? {
        try result.get()
    }
}
