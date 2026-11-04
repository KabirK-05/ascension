import Foundation

/// A food, carried per 100 g so a barcode, a USDA entry and a hand-built staple all
/// scale the same way (spec §7).
///
/// `servingGrams` is what a one-tap staple logs; it is `nil` for foods that only make
/// sense weighed. `docs/EXPORT_SCHEMA.md` names `FoodItem` in the `set_staples` payload
/// but does not pin its shape, so this follows spec §7 field for field.
public struct FoodItemDTO: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var brand: String?
    public var kcalPer100g: Double
    public var proteinPer100g: Double
    public var fatPer100g: Double
    public var carbsPer100g: Double
    public var source: FoodSource
    public var barcode: String?
    public var servingGrams: Double?
    public var servingName: String?

    public init(id: String, name: String, brand: String? = nil, kcalPer100g: Double,
                proteinPer100g: Double, fatPer100g: Double, carbsPer100g: Double,
                source: FoodSource, barcode: String? = nil,
                servingGrams: Double? = nil, servingName: String? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.fatPer100g = fatPer100g
        self.carbsPer100g = carbsPer100g
        self.source = source
        self.barcode = barcode
        self.servingGrams = servingGrams
        self.servingName = servingName
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeNullable(brand, forKey: .brand)
        try container.encode(kcalPer100g, forKey: .kcalPer100g)
        try container.encode(proteinPer100g, forKey: .proteinPer100g)
        try container.encode(fatPer100g, forKey: .fatPer100g)
        try container.encode(carbsPer100g, forKey: .carbsPer100g)
        try container.encode(source, forKey: .source)
        try container.encodeNullable(barcode, forKey: .barcode)
        try container.encodeNullable(servingGrams, forKey: .servingGrams)
        try container.encodeNullable(servingName, forKey: .servingName)
    }
}

/// Absolute macros for a weighed portion.
public struct Macros: Hashable, Sendable {
    public var kcal: Double
    public var proteinG: Double
    public var fatG: Double
    public var carbsG: Double

    public init(kcal: Double, proteinG: Double, fatG: Double, carbsG: Double) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
    }
}

extension FoodItemDTO {
    public func macros(forGrams grams: Double) -> Macros {
        let scale = grams / 100
        return Macros(kcal: kcalPer100g * scale,
                      proteinG: proteinPer100g * scale,
                      fatG: fatPer100g * scale,
                      carbsG: carbsPer100g * scale)
    }

    /// The macros a one-tap staple logs, or `nil` when the food has no default serving.
    public var servingMacros: Macros? {
        guard let servingGrams else { return nil }
        return macros(forGrams: servingGrams)
    }
}
