import AscensionCore
import Foundation

/// Whole foods from USDA FoodData Central (spec §10; the data is CC0).
///
/// The key is the user's own and lives in the Keychain (spec §8) — it is never in the
/// repo and never in a URL query, so it travels in the `X-Api-Key` header. With no key
/// the search path reports `missingAPIKey` and the rest of the tab is unaffected.
public struct USDAFoodSearch: FoodSearching {
    private let http: any HTTPFetching
    private let keys: any APIKeyStore
    private let cache: any FoodCache
    private let filter: DietaryFilter
    private let pageSize: Int

    public init(http: any HTTPFetching = URLSessionHTTPFetching(),
                keys: any APIKeyStore,
                cache: any FoodCache,
                filter: DietaryFilter = DietaryFilter(),
                pageSize: Int = 20) {
        self.http = http
        self.keys = keys
        self.cache = cache
        self.filter = filter
        self.pageSize = pageSize
    }

    public func search(_ query: String) async throws -> [FoodItemDTO] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        guard let key = keys.apiKey(for: .usda) else { throw FoodLookupError.missingAPIKey }

        do {
            let payload = try await fetch(term: term, key: key)
            let foods = payload.foods.compactMap { convert($0) }
            await cache.store(foods, forSearch: term)
            return foods
        } catch let error as FoodLookupError where error == .offline {
            // Offline is not an error the user needs to read about when the same
            // search has been run before: the cached answer is still true.
            let cached = await cache.foods(forSearch: term)
            if cached.isEmpty { throw error }
            return cached
        }
    }

    private func fetch(term: String, key: String) async throws -> SearchPayload {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy")
        ]
        guard let url = components?.url else { throw FoodLookupError.unusableResponse }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await http.data(for: request)
        guard response.statusCode == 200 else {
            throw FoodLookupError.http(response.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(SearchPayload.self, from: data) else {
            throw FoodLookupError.unusableResponse
        }
        return payload
    }

    private func convert(_ food: USDAFood) -> FoodItemDTO? {
        let nutrients = Dictionary(
            food.foodNutrients?.compactMap { nutrient -> (Int, Double)? in
                guard let id = nutrient.nutrientId, let value = nutrient.value else { return nil }
                return (id, value)
            } ?? [],
            uniquingKeysWith: { first, _ in first })

        let candidate = FoodItemDTO(
            id: "usda_\(food.fdcId)",
            name: food.description,
            brand: food.brandOwner,
            kcalPer100g: nutrients[Nutrient.energyKcal] ?? 0,
            proteinPer100g: nutrients[Nutrient.protein] ?? 0,
            fatPer100g: nutrients[Nutrient.fat] ?? 0,
            carbsPer100g: nutrients[Nutrient.carbs] ?? 0,
            source: .usda)
        return RemoteFood.validated(candidate, filter: filter,
                                    extraText: [food.foodCategory].compactMap { $0 })
    }

    /// FoodData Central nutrient numbers. Fixed by the source, so they are constants
    /// rather than a lookup.
    private enum Nutrient {
        static let protein = 1003
        static let fat = 1004
        static let carbs = 1005
        static let energyKcal = 1008
    }
}

/// The slice of the FoodData Central search response this app reads.
private struct SearchPayload: Decodable {
    let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    let fdcId: Int
    let description: String
    let brandOwner: String?
    let foodCategory: String?
    let foodNutrients: [USDANutrient]?
}

private struct USDANutrient: Decodable {
    let nutrientId: Int?
    let value: Double?
}
