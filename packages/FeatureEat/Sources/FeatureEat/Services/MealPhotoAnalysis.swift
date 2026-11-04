import AscensionCore
import Foundation

/// A plate, photographed, estimated (spec §F3 v2: "photo → macros parsing … Claude API
/// only if the user adds their own key").
///
/// Behind a protocol for the same reason the two food databases are: the screen's logic
/// is tested without a network, and every degraded path — no key, no network, a reply
/// this app will not use — is a case a test can produce.
public protocol MealPhotoAnalysing: Sendable {
    /// JPEG bytes in, candidate foods out. Throws `MealAnalysisError`.
    func foods(inPhoto jpeg: Data) async throws -> [AnalysedFood]
}

/// One food an estimate claims is on the plate, with the macros of the portion shown —
/// not per 100 g, because that is not a thing a photograph can be read for.
///
/// Deliberately not a `FoodItemDTO`: a `FoodItemDTO` is a food the app knows, and this is
/// a guess. It becomes one only after the user has looked at it and accepted it
/// (`portion()` below), which is the whole point of the confirm step.
public struct AnalysedFood: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let grams: Double
    public let macros: Macros

    public init(id: String = UUID().uuidString, name: String, grams: Double, macros: Macros) {
        self.id = id
        self.name = name
        self.grams = grams
        self.macros = macros
    }

    /// The portion this estimate stands for, scaled to per-100 g like every other food in
    /// this feature so a change of grams scales it the same way.
    ///
    /// `nil` for a zero-gram estimate: there is nothing to scale from, and a food whose
    /// per-100 g figures are a division by zero must not reach Apple Health.
    public func portion() -> Portion? {
        guard grams > 0 else { return nil }
        let per100 = 100 / grams
        let food = FoodItemDTO(
            id: "photo_\(id)",
            name: name,
            kcalPer100g: macros.kcal * per100,
            proteinPer100g: macros.proteinG * per100,
            fatPer100g: macros.fatG * per100,
            carbsPer100g: macros.carbsG * per100,
            // `custom`, because that is what it is: a food the user accepted by hand.
            // `FoodSource` is `AscensionCore`'s and the export's, and a photo estimate is
            // not a new kind of source worth changing the schema for.
            source: .custom)
        return Portion(food: food, grams: grams)
    }
}

public enum MealAnalysisError: Error, Equatable {
    /// No Claude key in the Keychain. Everything else on this tab is unaffected.
    case missingAPIKey
    /// The user has not agreed to send photographs off the device.
    case notPermitted
    case offline
    /// The model answered, but with nothing this app will put in front of the user:
    /// unparseable, empty, out of range, or nothing left after the dietary filter.
    case unusableResponse
    case http(Int)
}
