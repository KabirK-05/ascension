import AscensionCore
import Foundation
import Testing

@testable import FeatureEat

/// ASC-24's second half: a photograph becomes an editable estimate, and every way that
/// can fail leaves the rest of the tab exactly as it was.
@Suite("Photo to macros")
struct PhotoAnalysisTests {

    private static let photo = Data("not-really-a-jpeg".utf8)

    private static func reply(_ json: String, stop: String = "end_turn") -> String {
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
        return """
            {"content":[{"type":"text","text":"\(escaped)"}],"stop_reason":"\(stop)"}
            """
    }

    private static let plate = reply("""
        {"foods":[{"name":"Chicken breast","grams":200,"kcal":330,\
        "protein_g":62,"fat_g":7.2,"carbs_g":0},\
        {"name":"White rice","grams":250,"kcal":325,\
        "protein_g":6.8,"fat_g":0.8,"carbs_g":70}]}
        """)

    private func vision(_ http: StubHTTP,
                        key: String? = "sk-test",
                        granted: Bool = true) -> AnthropicMealVision {
        AnthropicMealVision(keys: EphemeralAPIKeyStore(keys: key.map { [.anthropic: $0] } ?? [:]),
                            http: http,
                            consent: EphemeralMealPhotoConsent(granted: granted))
    }

    // MARK: The happy path

    @Test("a plate comes back as one estimate per food")
    func readsEachFoodOnThePlate() async throws {
        let found = try await vision(.json(Self.plate)).foods(inPhoto: Self.photo)

        #expect(found.map(\.name) == ["Chicken breast", "White rice"])
        #expect(found.first?.grams == 200)
        #expect(found.first?.macros.proteinG == 62)
    }

    @Test("an estimate scales like every other food, by grams")
    func estimateScalesByGrams() async throws {
        let found = try await vision(.json(Self.plate)).foods(inPhoto: Self.photo)
        let chicken = try #require(found.first)
        let portion = try #require(chicken.portion())

        // 62 g of protein in 200 g is 31 g per 100 g — the shape `Portion` scales from.
        #expect(portion.food.proteinPer100g == 31)
        #expect(portion.macros.proteinG == 62)
        let half = Portion(food: portion.food, grams: 100)
        #expect(half.macros.proteinG == 31)
    }

    @Test("the request carries the photo and the model, and never logs the key")
    func sendsTheRightRequest() async throws {
        let seen = Captured()
        let stub = StubHTTP.json(Self.plate) { request in seen.record(request) }
        _ = try await vision(stub).foods(inPhoto: Self.photo)

        let request = try #require(seen.request)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-opus-5-5")
        #expect(json["output_config"] != nil)

        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let image = try #require(content.first)
        #expect(image["type"] as? String == "image")
        let source = try #require(image["source"] as? [String: Any])
        #expect(source["media_type"] as? String == "image/jpeg")
        #expect(source["data"] as? String == Self.photo.base64EncodedString())
    }

    // MARK: The dietary rule

    @Test("a photo of a burger does not become a beef entry")
    func dropsExcludedMeats() async throws {
        let body = Self.reply("""
            {"foods":[{"name":"Beef burger","grams":180,"kcal":500,\
            "protein_g":30,"fat_g":30,"carbs_g":30},\
            {"name":"Chicken breast","grams":100,"kcal":165,\
            "protein_g":31,"fat_g":3.6,"carbs_g":0}]}
            """)
        let found = try await vision(.json(body)).foods(inPhoto: Self.photo)

        #expect(found.map(\.name) == ["Chicken breast"])
    }

    @Test("a plate of nothing but pork is an unusable answer, not an empty one")
    func everythingExcludedIsUnusable() async {
        let body = Self.reply("""
            {"foods":[{"name":"Bacon","grams":50,"kcal":250,\
            "protein_g":15,"fat_g":20,"carbs_g":0}]}
            """)
        await #expect(throws: MealAnalysisError.unusableResponse) {
            try await vision(.json(body)).foods(inPhoto: Self.photo)
        }
    }

    @Test("a figure no food can have is dropped rather than clamped")
    func dropsImpossibleFigures() async {
        // 95 g of protein in 100 g, which no food is.
        let body = Self.reply("""
            {"foods":[{"name":"Mystery","grams":100,"kcal":400,\
            "protein_g":95,"fat_g":50,"carbs_g":60}]}
            """)
        await #expect(throws: MealAnalysisError.unusableResponse) {
            try await vision(.json(body)).foods(inPhoto: Self.photo)
        }
    }

    @Test("a zero-gram estimate has nothing to scale from and is dropped")
    func dropsZeroGramEstimates() async {
        let body = Self.reply("""
            {"foods":[{"name":"Air","grams":0,"kcal":0,\
            "protein_g":0,"fat_g":0,"carbs_g":0}]}
            """)
        await #expect(throws: MealAnalysisError.unusableResponse) {
            try await vision(.json(body)).foods(inPhoto: Self.photo)
        }
    }

    // MARK: Degrading honestly

    @Test("no key is its own answer, and it never reaches the network")
    func refusesWithoutAKey() async {
        let seen = Captured()
        let stub = StubHTTP.json(Self.plate) { request in seen.record(request) }
        await #expect(throws: MealAnalysisError.missingAPIKey) {
            try await vision(stub, key: nil).foods(inPhoto: Self.photo)
        }
        #expect(seen.request == nil)
    }

    @Test("without consent nothing leaves the device, key or no key")
    func refusesWithoutConsent() async {
        let seen = Captured()
        let stub = StubHTTP.json(Self.plate) { request in seen.record(request) }
        await #expect(throws: MealAnalysisError.notPermitted) {
            try await vision(stub, granted: false).foods(inPhoto: Self.photo)
        }
        #expect(seen.request == nil)
    }

    @Test("offline is offline")
    func reportsOffline() async {
        await #expect(throws: FoodLookupError.offline) {
            try await vision(.offline).foods(inPhoto: Self.photo)
        }
    }

    @Test("an HTTP failure carries its status")
    func reportsHTTPFailure() async {
        await #expect(throws: MealAnalysisError.http(401)) {
            try await vision(.json("{}", status: 401)).foods(inPhoto: Self.photo)
        }
    }

    @Test("a reply this app cannot read is unusable, not a guess")
    func rejectsUnreadableReplies() async {
        for body in ["not json at all",
                     #"{"content":[]}"#,
                     Self.reply(#"{"foods":[]}"#),
                     Self.reply("{\"wrong\":1}")] {
            await #expect(throws: MealAnalysisError.unusableResponse) {
                try await vision(.json(body)).foods(inPhoto: Self.photo)
            }
        }
    }

    @Test("a declined or truncated turn is never read as an estimate")
    func rejectsRefusedAndTruncatedTurns() async {
        for stop in ["refusal", "max_tokens"] {
            await #expect(throws: MealAnalysisError.unusableResponse) {
                try await vision(.json(Self.reply(Self.plateJSON, stop: stop)))
                    .foods(inPhoto: Self.photo)
            }
        }
    }

    @Test("an empty photo is not sent")
    func refusesAnEmptyPhoto() async {
        await #expect(throws: MealAnalysisError.unusableResponse) {
            try await vision(.json(Self.plate)).foods(inPhoto: Data())
        }
    }

    private static let plateJSON = """
        {"foods":[{"name":"Chicken breast","grams":200,"kcal":330,\
        "protein_g":62,"fat_g":7.2,"carbs_g":0}]}
        """
}

/// ASC-24: the photo path is an addition, so every one of its failures has to leave the
/// screen usable and say what happened in as few words as the outcome has.
@Suite("Photo states")
@MainActor
struct PhotoStateTests {

    private func model(_ photos: (any MealPhotoAnalysing)?) -> EatModel {
        EatModel(dependencies: EatDependencies(diary: InMemoryMealDiaryStore(),
                                               writeBack: RecordingWriteBack(),
                                               photos: photos),
                 date: EatSamples.day,
                 now: { EatSamples.day.date() ?? Date() })
    }

    private var sample: AnalysedFood {
        AnalysedFood(name: "Chicken breast", grams: 200,
                     macros: Macros(kcal: 330, proteinG: 62, fatG: 7.2, carbsG: 0))
    }

    @Test("a reading returns its foods and clears the state")
    func readingSucceeds() async {
        let subject = model(StubPhotoAnalysis(result: .success([sample])))
        let found = await subject.foods(inPhoto: Data([1, 2, 3]))

        #expect(found.count == 1)
        #expect(subject.photoState == .idle)
    }

    @Test("each failure maps to the one word that describes it")
    func failuresMapToStates() async {
        let cases: [(any Error, EatModel.PhotoState)] = [
            (MealAnalysisError.missingAPIKey, .keyMissing),
            (MealAnalysisError.notPermitted, .notPermitted),
            (MealAnalysisError.offline, .offline),
            (MealAnalysisError.unusableResponse, .unusable),
            (MealAnalysisError.http(500), .failed)
        ]
        for (error, expected) in cases {
            let subject = model(StubPhotoAnalysis(result: .failure(error)))
            let found = await subject.foods(inPhoto: Data([1]))
            #expect(found.isEmpty)
            #expect(subject.photoState == expected)
        }
    }

    @Test("no analyser at all leaves the menu without a photo entry")
    func noAnalyserIsNotOffered() {
        #expect(model(nil).isPhotoAvailable == false)
        #expect(model(StubPhotoAnalysis(result: .success([]))).isPhotoAvailable)
    }

    @Test("a photo that fails leaves staples, barcode and search untouched")
    func failureDoesNotDisturbTheRestOfTheTab() async throws {
        let subject = model(StubPhotoAnalysis(result: .failure(MealAnalysisError.offline)))
        _ = await subject.foods(inPhoto: Data([1]))

        let omelette = try #require(Seed.stapleFoods.first)
        #expect(await subject.logStaple(omelette) != nil)
        #expect(subject.entries.count == 1)
        #expect(subject.searchState == .idle)
        #expect(subject.barcodeState == .idle)
    }

    @Test("nothing is logged by reading a photo — the user confirms first")
    func readingLogsNothing() async {
        let subject = model(StubPhotoAnalysis(result: .success([sample])))
        _ = await subject.foods(inPhoto: Data([1]))

        #expect(subject.entries.isEmpty)
    }
}

/// Captures the one request a stub was handed, across the `@Sendable` boundary.
final class Captured: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: URLRequest?

    var request: URLRequest? { lock.withLock { captured } }

    func record(_ request: URLRequest) {
        lock.withLock { captured = request }
    }
}
