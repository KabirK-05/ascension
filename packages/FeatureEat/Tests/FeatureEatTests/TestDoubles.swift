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

/// Records what the Eat tab would have written to Apple Health.
final class RecordingWriteBack: NutritionWriteBack, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [NutritionSample] = []
    private let outcome: NutritionWriteOutcome
    private let failure: (any Error)?

    init(outcome: NutritionWriteOutcome = .written, failure: (any Error)? = nil) {
        self.outcome = outcome
        self.failure = failure
    }

    var written: [NutritionSample] { lock.withLock { samples } }

    func write(_ sample: NutritionSample) async throws -> NutritionWriteOutcome {
        if let failure { throw failure }
        lock.withLock { samples.append(sample) }
        return outcome
    }
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
