import AscensionCore
import Foundation

/// The photo path, over the Anthropic Messages API with the user's own key (spec §F3,
/// §8: "optional Claude key … in Keychain, never in the repo").
///
/// **Why the API and not `FoundationModels`.** The on-device model is free, private and
/// already on this phone, and it is the right tool for the *text* path ("2 eggs and
/// toast"). It is text-only, so a photograph cannot go through it. That is the whole
/// reason this network call exists, and it is why the feature is opt-in and degradable
/// rather than a dependency: with no key, no consent or no network, barcode, search,
/// staples and manual entry are untouched.
///
/// **What leaves the device.** One JPEG and one prompt, to `api.anthropic.com`, only
/// after the user has agreed at the point of use (`MealPhotoConsent`). Nothing else: no
/// diary, no targets, no identifiers. The key is read from the Keychain per call and is
/// never logged — `URLRequest` headers are never printed anywhere in this package.
public struct AnthropicMealVision: MealPhotoAnalysing {
    /// One constant so the model is one line to change. Claude Opus 5.5 is the current
    /// default model; a cheaper one would be a cost decision, and the key is the user's.
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")
    static let apiVersion = "2026-10-21"
    /// Enough for a plate's worth of rows and no more.
    static let maxTokens = 2048
    /// A photo larger than this is a cost with no accuracy behind it; the caller
    /// downscales before it gets here, and this is the backstop.
    static let maxPhotoBytes = 4 * 1024 * 1024

    private let keys: any APIKeyStore
    private let http: any HTTPFetching
    private let consent: any MealPhotoConsenting
    private let filter: DietaryFilter

    public init(keys: any APIKeyStore,
                http: any HTTPFetching = URLSessionHTTPFetching(),
                consent: any MealPhotoConsenting,
                filter: DietaryFilter = DietaryFilter()) {
        self.keys = keys
        self.http = http
        self.consent = consent
        self.filter = filter
    }

    public func foods(inPhoto jpeg: Data) async throws -> [AnalysedFood] {
        guard consent.isGranted else { throw MealAnalysisError.notPermitted }
        guard let key = keys.apiKey(for: .anthropic) else { throw MealAnalysisError.missingAPIKey }
        guard !jpeg.isEmpty, jpeg.count <= Self.maxPhotoBytes,
              let endpoint = Self.endpoint else {
            throw MealAnalysisError.unusableResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try body(jpeg: jpeg)

        let (data, response) = try await http.data(for: request)
        guard response.statusCode == 200 else { throw MealAnalysisError.http(response.statusCode) }
        return try parse(data)
    }

    // MARK: - Request

    private func body(jpeg: Data) throws -> Data {
        let payload: [String: Any] = [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            // A schema rather than "reply in JSON": the response is parsed straight into
            // numbers that the user edits and then writes to Apple Health, and a prose
            // reply would have to be scraped.
            "output_config": ["format": ["type": "json_schema", "schema": Self.schema]],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64",
                                "media_type": "image/jpeg",
                                "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": Self.prompt]
                ]
            ]]
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else {
            throw MealAnalysisError.unusableResponse
        }
        return encoded
    }

    /// Totals for the portion in the picture, not per 100 g: a photograph shows a plate,
    /// and asking for a density would invite the model to invent one.
    ///
    /// Built per call rather than held as a `static let`: `[String: Any]` is not
    /// `Sendable`, and a shared mutable dictionary is exactly what Swift 6 is right to
    /// refuse. It costs nothing next to the request it goes into.
    static var schema: [String: Any] {[
        "type": "object",
        "properties": [
            "foods": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "grams": ["type": "number"],
                        "kcal": ["type": "number"],
                        "protein_g": ["type": "number"],
                        "fat_g": ["type": "number"],
                        "carbs_g": ["type": "number"]
                    ],
                    "required": ["name", "grams", "kcal", "protein_g", "fat_g", "carbs_g"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["foods"],
        "additionalProperties": false
    ]}

    static let prompt = """
        Identify each distinct food in this photograph of a meal and estimate, for the \
        portion visible, its weight in grams and its calories, protein, fat and \
        carbohydrate in grams.

        One entry per food, not one per plate: rice and chicken on the same plate are two \
        entries. Name each food plainly and briefly, as a food label would. If the \
        photograph shows no food, return an empty list rather than a guess.
        """

    // MARK: - Response

    private func parse(_ data: Data) throws -> [AnalysedFood] {
        guard let envelope = try? JSONDecoder().decode(MealVisionEnvelope.self, from: data) else {
            throw MealAnalysisError.unusableResponse
        }
        // A declined or truncated turn is not an estimate. Checked before the content is
        // read, because a truncated reply can still parse into plausible-looking numbers.
        guard envelope.stopReason != "refusal", envelope.stopReason != "max_tokens" else {
            throw MealAnalysisError.unusableResponse
        }
        guard let text = envelope.content.first(where: { $0.type == "text" })?.text,
              let estimate = try? JSONDecoder().decode(MealVisionEstimate.self, from: Data(text.utf8)) else {
            throw MealAnalysisError.unusableResponse
        }
        let foods = estimate.foods.compactMap(validated)
        guard !foods.isEmpty else { throw MealAnalysisError.unusableResponse }
        return foods
    }

    /// Every row is checked before it is shown, on the same terms as a barcode or a
    /// search hit: spec §2's dietary rule is a hard constraint, so a photograph of a
    /// burger must not become a beef entry, and `RemoteFood` keeps a nonsense figure out
    /// of a field the user might accept without reading.
    private func validated(_ row: MealVisionRow) -> AnalysedFood? {
        guard !DietaryFilter.isExcluded(row.name) else { return nil }
        let food = AnalysedFood(name: row.name, grams: row.grams,
                                macros: Macros(kcal: row.kcal, proteinG: row.proteinG,
                                               fatG: row.fatG, carbsG: row.carbsG))
        guard let portion = food.portion(),
              Self.isPlausible(portion.food),
              let clean = RemoteFood.validated(portion.food, filter: filter) else { return nil }
        return AnalysedFood(id: food.id, name: clean.name, grams: food.grams,
                            macros: food.macros)
    }

    /// One check `RemoteFood` does not make, for the one source that needs it.
    ///
    /// `RemoteFood` bounds each macro on its own, which is the right shape for a
    /// database row. An estimate has a failure mode a database does not: the three
    /// macros can each be believable and still weigh more together than the food does.
    /// Kept here rather than widened into `RemoteFood`, because changing that would
    /// change what a barcode and a search return, and neither has this problem.
    static func isPlausible(_ food: FoodItemDTO) -> Bool {
        // Five grams of slack for rounding; the figure being caught is far past that.
        food.proteinPer100g + food.fatPer100g + food.carbsPer100g <= 105
    }
}

/// What the Messages API hands back, as much of it as this feature reads.
///
/// File scope rather than nested: four levels of nesting is one more than SwiftLint
/// allows here, and these are a wire format rather than part of the caller's vocabulary.
private struct MealVisionEnvelope: Decodable {
    let content: [Block]
    let stopReason: String?

    struct Block: Decodable {
        let type: String
        let text: String?
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

/// The JSON the schema asks for: totals for the portion in the picture.
private struct MealVisionEstimate: Decodable {
    let foods: [MealVisionRow]
}

private struct MealVisionRow: Decodable {
    let name: String
    let grams: Double
    let kcal: Double
    let proteinG: Double
    let fatG: Double
    let carbsG: Double

    enum CodingKeys: String, CodingKey {
        case name, grams, kcal
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
    }
}
