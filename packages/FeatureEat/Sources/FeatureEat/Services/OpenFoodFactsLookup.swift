import AscensionCore
import Foundation

/// Packaged food by barcode, from Open Food Facts (spec §10).
///
/// ODbL, so the attribution in `EatCredits` is a licence term, not a courtesy. No key
/// is needed, but the API asks every client to identify itself, which the User-Agent
/// does. Every answer is cached by barcode: the same tin scanned in a shop with no
/// signal should still log.
public struct OpenFoodFactsLookup: BarcodeLookup {
    private let http: any HTTPFetching
    private let cache: any FoodCache
    private let filter: DietaryFilter

    public init(http: any HTTPFetching = URLSessionHTTPFetching(),
                cache: any FoodCache,
                filter: DietaryFilter = DietaryFilter()) {
        self.http = http
        self.cache = cache
        self.filter = filter
    }

    public func food(barcode: String) async throws -> FoodItemDTO? {
        let code = barcode.filter(\.isNumber)
        guard (8...14).contains(code.count) else { throw FoodLookupError.unusableResponse }

        do {
            let food = try await fetch(code: code)
            if let food { await cache.store(food, forBarcode: code) }
            return food
        } catch let error as FoodLookupError where error == .offline {
            guard let cached = await cache.food(forBarcode: code) else { throw error }
            return cached
        }
    }

    private func fetch(code: String) async throws -> FoodItemDTO? {
        let fields = "code,product_name,brands,categories_tags,ingredients_text,"
            + "serving_quantity,serving_size,nutriments"
        guard let url = URL(string:
            "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)") else {
            throw FoodLookupError.unusableResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Ascension/0.1 (personal health manager)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await http.data(for: request)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw FoodLookupError.http(response.statusCode) }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw FoodLookupError.unusableResponse
        }
        guard let product = payload.product else { return nil }
        return convert(product, code: code)
    }

    private func convert(_ product: OFFProduct, code: String) -> FoodItemDTO? {
        guard let name = product.productName, !name.isEmpty else { return nil }
        let nutriments = product.nutriments

        let candidate = FoodItemDTO(
            id: "off_\(code)",
            name: name,
            brand: product.brands,
            kcalPer100g: nutriments?.energyKcal100g ?? 0,
            proteinPer100g: nutriments?.proteins100g ?? 0,
            fatPer100g: nutriments?.fat100g ?? 0,
            carbsPer100g: nutriments?.carbohydrates100g ?? 0,
            source: .off,
            barcode: code,
            servingGrams: product.servingQuantity?.value,
            servingName: product.servingSize)
        let text = (product.categoriesTags ?? []) + [product.ingredientsText].compactMap { $0 }
        return RemoteFood.validated(candidate, filter: filter, extraText: text)
    }
}

/// A JSON number Open Food Facts sometimes quotes.
private struct LenientDouble: Decodable {
    let value: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }
}

private struct Payload: Decodable {
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let categoriesTags: [String]?
    let ingredientsText: String?
    /// A number on some products and a string on others.
    let servingQuantity: LenientDouble?
    let servingSize: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case categoriesTags = "categories_tags"
        case ingredientsText = "ingredients_text"
        case servingQuantity = "serving_quantity"
        case servingSize = "serving_size"
        case nutriments
    }
}

private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let fat100g: Double?
    let carbohydrates100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case fat100g = "fat_100g"
        case carbohydrates100g = "carbohydrates_100g"
    }
}
