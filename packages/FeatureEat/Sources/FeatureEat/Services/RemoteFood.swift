import AscensionCore
import Foundation

/// Everything a remote source says is untrusted until it has been through here.
///
/// Two reasons. A figure that is nonsense would land in Apple Health as fact, and
/// spec §12 forbids pork and beef reaching the user at all — neither can be left to
/// the view. A food that fails any check is dropped, not clamped: a silently corrected
/// macro is worse than a missing search result.
public enum RemoteFood {
    /// Per 100 g, nothing can exceed these and still be food. Pure fat is 900 kcal and
    /// 100 g, which is the ceiling in both cases.
    static let kcalRange: ClosedRange<Double> = 0...900
    static let gramsPer100gRange: ClosedRange<Double> = 0...100
    static let nameLengthLimit = 80
    /// A serving outside this is a data-entry error at the source, not a portion.
    static let servingRange: ClosedRange<Double> = 1...5000

    public static func validated(_ food: FoodItemDTO,
                                 filter: DietaryFilter = DietaryFilter(),
                                 extraText: [String] = []) -> FoodItemDTO? {
        guard filter.allows(food, extraText: extraText) else { return nil }
        let name = trimmed(food.name)
        guard !name.isEmpty else { return nil }
        guard within(food.kcalPer100g, kcalRange),
              within(food.proteinPer100g, gramsPer100gRange),
              within(food.fatPer100g, gramsPer100gRange),
              within(food.carbsPer100g, gramsPer100gRange) else { return nil }

        var clean = food
        clean.name = name
        clean.brand = food.brand.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
        clean.servingGrams = food.servingGrams.flatMap { within($0, servingRange) ? $0 : nil }
        clean.servingName = clean.servingGrams == nil ? nil : food.servingName
        return clean
    }

    private static func within(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value)
    }

    private static func trimmed(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(nameLengthLimit))
    }
}
