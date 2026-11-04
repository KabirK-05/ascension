import AscensionCore
import Foundation
import Testing

@testable import FeatureEat

/// Spec §2 and §12: chicken and eggs are the only meats. These are the tests that
/// stop a search result, a barcode or a recent putting pork or beef in front of the
/// user — a product requirement, not a preference.
@Suite("Pork and beef never surface")
struct DietaryFilterTests {

    @Test("pork and beef products are excluded", arguments: [
        "Pork belly", "Smoked bacon", "Ground beef 80/20", "Beef mince",
        "Serrano ham", "Chorizo picante", "Salami Milano", "Veal escalope",
        "Pepperoni pizza", "Prosciutto di Parma", "Jamón ibérico", "Lard",
        "en:pork-products", "Cheeseburger", "Pulled pork"
    ])
    func excludesPorkAndBeef(_ text: String) {
        #expect(DietaryFilter.isExcluded(text))
    }

    @Test("the foods this user actually eats are allowed", arguments: [
        "Chicken breast, roasted", "Chicken thighs", "Egg, whole, cooked",
        "Rice, white, cooked", "Potatoes, boiled", "Rolled oats",
        "Milk with Bournvita", "Beefsteak tomato", "Chicken sausage", "Greek salad"
    ])
    func allowsTheRest(_ text: String) {
        #expect(!DietaryFilter.isExcluded(text))
    }

    /// The rule errs towards exclusion. Spec §12 says pork and beef must never
    /// surface, so a burger product that names no meat is excluded even though the bun
    /// alone would be fine — a false positive costs one custom food, a false negative
    /// breaks a hard constraint.
    @Test("an ambiguous burger product is excluded rather than risked", arguments: [
        "Hamburger", "Hamburger bun", "Cheeseburger deluxe"
    ])
    func excludesAmbiguousBurgers(_ text: String) {
        #expect(DietaryFilter.isExcluded(text))
    }

    @Test("a food is checked on its brand and its category tags, not only its name")
    func checksEveryField() {
        let filter = DietaryFilter()
        let innocentName = FoodItemDTO(
            id: "off_1", name: "Smoked rashers", brand: "Denny",
            kcalPer100g: 250, proteinPer100g: 15, fatPer100g: 20, carbsPer100g: 1,
            source: .off)

        #expect(filter.allows(innocentName))
        #expect(!filter.allows(innocentName, extraText: ["en:pork", "en:meats"]))
    }

    @Test("filtering a list keeps the order of what survives")
    func filtersLists() {
        let filter = DietaryFilter()
        let pork = FoodItemDTO(id: "off_2", name: "Pork sausage", kcalPer100g: 300,
                               proteinPer100g: 13, fatPer100g: 27, carbsPer100g: 2,
                               source: .off)
        let kept = filter.allowed([EatSamples.chickenBreast, pork, EatSamples.egg])

        #expect(kept.map(\.id) == [EatSamples.chickenBreast.id, EatSamples.egg.id])
    }

    @Test("a USDA search drops excluded results before they reach the screen")
    func searchFiltersResults() async throws {
        let body = """
        {"foods":[
          {"fdcId":1,"description":"Beef, ground, raw","foodNutrients":[
            {"nutrientId":1008,"value":250},{"nutrientId":1003,"value":17}]},
          {"fdcId":2,"description":"Chicken, breast, roasted","foodNutrients":[
            {"nutrientId":1008,"value":165},{"nutrientId":1003,"value":31},
            {"nutrientId":1004,"value":3.6},{"nutrientId":1005,"value":0}]}
        ]}
        """
        let search = USDAFoodSearch(http: StubHTTP.json(body),
                                    keys: EphemeralAPIKeyStore(keys: [.usda: "test-key"]),
                                    cache: MemoryFoodCache())

        let found = try await search.search("meat")

        #expect(found.count == 1)
        #expect(found.first?.name == "Chicken, breast, roasted")
        #expect(found.first?.proteinPer100g == 31)
    }

    @Test("a barcode for a pork product returns nothing to show")
    func barcodeFiltersProducts() async throws {
        let body = """
        {"product":{"product_name":"Smoked rashers","brands":"Denny",
         "categories_tags":["en:meats","en:pork"],
         "nutriments":{"energy-kcal_100g":250,"proteins_100g":15,
          "fat_100g":20,"carbohydrates_100g":1}}}
        """
        let lookup = OpenFoodFactsLookup(http: StubHTTP.json(body), cache: MemoryFoodCache())

        #expect(try await lookup.food(barcode: "5000108501000") == nil)
    }
}
