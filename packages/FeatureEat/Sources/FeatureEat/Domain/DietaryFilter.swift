import AscensionCore
import Foundation

/// Spec §2 and §12, enforced: chicken and eggs are the only meats, so nothing made of
/// pork or beef may reach a search result, a barcode result, a recent or a sample.
///
/// This is a product constraint, not a preference, so it is applied at the boundary —
/// every remote food passes through `allows(_:)` before it is ever shown — rather than
/// trusted to each call site.
///
/// Matching is on whole words, after case folding and stripping diacritics, over the
/// name, the brand and whatever category or ingredient text the source supplies. Whole
/// words rather than substrings: `beef` as a substring rejects a beefsteak tomato, and
/// `ham` rejects anything hyphenated around it. Compound names that are in practice
/// pork or beef — `hamburger`, `porkchop` — are listed in full instead.
///
/// Where a name is ambiguous the rule excludes. A burger product that names no meat is
/// dropped: a false positive costs one custom food, a false negative breaks a hard
/// product constraint.
public struct DietaryFilter: Sendable {

    /// Single words that mean pork or beef, in English and in the forms Open Food Facts
    /// category tags use (`en:pork`, `pork-products`).
    private static let excludedWords: Set<String> = [
        "pork", "porks", "beef", "beefs", "bacon", "ham", "hams", "gammon",
        "veal", "lard", "prosciutto", "pancetta", "salami", "salame", "pepperoni",
        "chorizo", "bratwurst", "mortadella", "bologna", "pastrami", "speck",
        "jamon", "brisket", "oxtail", "tallow", "guanciale", "capicola", "soppressata",
        "porkchop", "porkchops", "beefburger", "beefburgers", "hamburger",
        "hamburgers", "cheeseburger", "cheeseburgers", "meatloaf", "liverwurst"
    ]

    /// Two-word phrases that only the pair makes excluded — neither word alone does.
    private static let excludedPhrases: [String] = [
        "ground chuck", "minced meat", "pulled pork", "corned meat"
    ]

    public init() {}

    /// Whether a food may be shown. Checks every text the source gave us, because a
    /// product named "Smoked Rashers" says what it is only in its category tags.
    public func allows(_ food: FoodItemDTO, extraText: [String] = []) -> Bool {
        let fields = [food.name, food.brand].compactMap { $0 } + extraText
        return !fields.contains { Self.isExcluded($0) }
    }

    public func allowed(_ foods: [FoodItemDTO]) -> [FoodItemDTO] {
        foods.filter { allows($0) }
    }

    /// Exposed so a test can assert on the rule itself rather than through a food.
    public static func isExcluded(_ text: String) -> Bool {
        let folded = fold(text)
        if excludedPhrases.contains(where: { folded.contains($0) }) { return true }
        return tokens(folded).contains { excludedWords.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
    }

    private static func tokens(_ folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
