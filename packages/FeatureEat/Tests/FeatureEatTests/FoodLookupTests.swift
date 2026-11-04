import AscensionCore
import Foundation
import Testing

@testable import FeatureEat

@Suite("USDA search")
struct USDASearchTests {

    private func search(http: any HTTPFetching, key: String? = "test-key",
                        cache: any FoodCache = MemoryFoodCache()) -> USDAFoodSearch {
        USDAFoodSearch(http: http,
                       keys: EphemeralAPIKeyStore(keys: key.map { [.usda: $0] } ?? [:]),
                       cache: cache)
    }

    @Test("with no key in the Keychain, search reports it rather than calling out")
    func missingKeyIsReported() async {
        let search = search(http: StubHTTP.json("{}"), key: nil)

        await #expect(throws: FoodLookupError.missingAPIKey) {
            _ = try await search.search("chicken")
        }
    }

    @Test("the key travels in a header, never in the URL")
    func keyIsNotInTheURL() async throws {
        let seen = SeenRequests()
        let search = search(http: StubHTTP.json(#"{"foods":[]}"#) { seen.record($0) })

        _ = try await search.search("chicken")
        let request = try #require(seen.last)

        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "test-key")
        #expect(request.url?.absoluteString.contains("test-key") == false)
    }

    @Test("an empty query never reaches the network")
    func emptyQueryShortCircuits() async throws {
        let search = search(http: StubHTTP(.failure(FoodLookupError.http(500))))

        #expect(try await search.search("   ").isEmpty)
    }

    @Test("offline falls back to the cached answer for the same search")
    func offlineUsesCache() async throws {
        let cache = MemoryFoodCache()
        let body = """
        {"foods":[{"fdcId":171077,"description":"Chicken breast, roasted",
         "foodNutrients":[{"nutrientId":1008,"value":165},{"nutrientId":1003,"value":31}]}]}
        """
        let online = search(http: StubHTTP.json(body), cache: cache)
        _ = try await online.search("chicken")

        let offline = search(http: StubHTTP.offline, cache: cache)
        let cached = try await offline.search("chicken")

        #expect(cached.map(\.name) == ["Chicken breast, roasted"])
    }

    @Test("offline with nothing cached reports offline")
    func offlineWithoutCache() async {
        let search = search(http: StubHTTP.offline)

        await #expect(throws: FoodLookupError.offline) {
            _ = try await search.search("chicken")
        }
    }

    @Test("a rejected key surfaces as the status it was")
    func httpErrorSurfaces() async {
        let search = search(http: StubHTTP.json("{}", status: 403))

        await #expect(throws: FoodLookupError.http(403)) {
            _ = try await search.search("chicken")
        }
    }

    @Test("a result with impossible macros is dropped, not clamped")
    func impossibleMacrosAreDropped() async throws {
        let body = """
        {"foods":[
          {"fdcId":1,"description":"Broken entry","foodNutrients":[
            {"nutrientId":1008,"value":9000},{"nutrientId":1003,"value":31}]},
          {"fdcId":2,"description":"Egg, whole, cooked","foodNutrients":[
            {"nutrientId":1008,"value":155},{"nutrientId":1003,"value":13},
            {"nutrientId":1004,"value":11},{"nutrientId":1005,"value":1.1}]}
        ]}
        """
        let found = try await search(http: StubHTTP.json(body)).search("egg")

        #expect(found.map(\.name) == ["Egg, whole, cooked"])
    }
}

@Suite("Open Food Facts barcodes")
struct BarcodeLookupTests {

    private let body = """
    {"product":{"product_name":"Rolled oats","brands":"Quaker",
     "categories_tags":["en:cereals"],"serving_quantity":"40","serving_size":"40 g",
     "nutriments":{"energy-kcal_100g":372,"proteins_100g":11.2,
      "fat_100g":8,"carbohydrates_100g":60}}}
    """

    @Test("a product becomes a food that scales by grams like any other")
    func decodesProduct() async throws {
        let lookup = OpenFoodFactsLookup(http: StubHTTP.json(body), cache: MemoryFoodCache())
        let food = try #require(try await lookup.food(barcode: "5000108501000"))

        #expect(food.source == .off)
        #expect(food.barcode == "5000108501000")
        #expect(food.servingGrams == 40)
        #expect((food.macros(forGrams: 80).proteinG * 100).rounded() == 896)
    }

    @Test("an unknown barcode is nothing found, not a failure")
    func unknownBarcode() async throws {
        let lookup = OpenFoodFactsLookup(http: StubHTTP.json("{}", status: 404),
                                         cache: MemoryFoodCache())

        #expect(try await lookup.food(barcode: "0000000000000") == nil)
    }

    @Test("a barcode that is not a barcode never reaches the network")
    func rejectsMalformedBarcodes() async {
        let lookup = OpenFoodFactsLookup(http: StubHTTP(.failure(FoodLookupError.http(500))),
                                         cache: MemoryFoodCache())

        await #expect(throws: FoodLookupError.unusableResponse) {
            _ = try await lookup.food(barcode: "12")
        }
    }

    @Test("a barcode scanned once logs again offline")
    func offlineUsesCachedProduct() async throws {
        let cache = MemoryFoodCache()
        let online = OpenFoodFactsLookup(http: StubHTTP.json(body), cache: cache)
        _ = try await online.food(barcode: "5000108501000")

        let offline = OpenFoodFactsLookup(http: StubHTTP.offline, cache: cache)
        let cached = try await offline.food(barcode: "5000108501000")

        #expect(cached?.name == "Rolled oats")
    }

    @Test("offline with nothing cached reports offline")
    func offlineWithoutCache() async {
        let lookup = OpenFoodFactsLookup(http: StubHTTP.offline, cache: MemoryFoodCache())

        await #expect(throws: FoodLookupError.offline) {
            _ = try await lookup.food(barcode: "5000108501000")
        }
    }
}

/// Captures the requests a stub was handed, across the concurrency boundary.
final class SeenRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var last: URLRequest? { lock.withLock { requests.last } }
}
