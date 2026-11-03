import AscensionCore
import Foundation
import Testing

@testable import FeatureEat

@Suite("Portion scaling")
struct PortionTests {

    @Test("a staple's serving reproduces the macros spec §2 quotes")
    func stapleServingMatchesSpec() throws {
        let chickenRice = try #require(
            Seed.stapleFoods.first { $0.id == "staple_chicken_breast_rice" })
        let portion = try #require(Portion(serving: chickenRice))

        #expect(portion.grams == 550)
        #expect(portion.macros.kcal.rounded() == 650)
        #expect(portion.macros.proteinG.rounded() == 55)
    }

    @Test("macros scale linearly with grams")
    func scalesLinearly() {
        let single = Portion(food: EatSamples.chickenBreast, grams: 100)
        let double = Portion(food: EatSamples.chickenBreast, grams: 200)

        #expect(single.macros.proteinG == 31)
        #expect(double.macros.proteinG == 62)
        #expect(double.macros.kcal == 330)
        #expect(double.macros.carbsG == 0)
    }

    @Test("a part portion scales down")
    func scalesDown() {
        let portion = Portion(food: EatSamples.rice, grams: 75)

        #expect(portion.macros.kcal == 97.5)
        #expect((portion.macros.carbsG * 10).rounded() / 10 == 21)
    }

    @Test("a negative portion is clamped to nothing rather than subtracting a meal")
    func negativeGramsAreClamped() {
        let portion = Portion(food: EatSamples.chickenBreast, grams: -200)

        #expect(portion.grams == 0)
        #expect(portion.macros.kcal == 0)
    }

    @Test("a food with no serving cannot be one-tapped")
    func noServingMeansNoOneTap() {
        #expect(Portion(serving: EatSamples.chickenBreast) == nil)
        #expect(Portion(serving: EatSamples.oats) != nil)
    }

    @Test("servings and grams agree in both directions")
    func servingsRoundTrip() throws {
        let portion = try #require(Portion(serving: EatSamples.oats))
        #expect(portion.servings == 1)

        let bigger = try #require(portion.scaled(toServings: 2.5))
        #expect(bigger.grams == 100)
        #expect(bigger.macros.proteinG == 11.2)
    }
}

@Suite("Macro arithmetic")
struct MacroArithmeticTests {

    @Test("a day sums every entry")
    func sumsEntries() {
        let totals = DayTotals(entries: EatSamples.entries(), targets: .seeded)
        let expected = Macros.total(EatSamples.entries().map(\.macros))

        #expect(totals.eaten.proteinG == expected.proteinG)
        #expect(totals.eaten.kcal == expected.kcal)
    }

    @Test("protein left is the target minus what was eaten, and never negative")
    func proteinRemaining() {
        let targets = NutritionTargets.seeded
        let eaten = Macros(kcal: 1200, proteinG: 110, fatG: 40, carbsG: 120)

        #expect(DayTotals(eaten: eaten, targets: targets).proteinRemainingG == 40)

        let over = Macros(kcal: 2400, proteinG: 172, fatG: 70, carbsG: 250)
        #expect(DayTotals(eaten: over, targets: targets).proteinRemainingG == 0)
    }

    @Test("the 140 g floor is what a day is scored against, not the 150 g target")
    func proteinFloor() {
        let targets = NutritionTargets.seeded
        let atFloor = Macros(kcal: 2000, proteinG: 140, fatG: 62, carbsG: 200)
        let below = Macros(kcal: 2000, proteinG: 139.5, fatG: 62, carbsG: 200)

        #expect(DayTotals(eaten: atFloor, targets: targets).clearedProteinFloor)
        #expect(!DayTotals(eaten: below, targets: targets).clearedProteinFloor)
    }

    @Test("carbs are the remainder of the calorie target, costed at the fat midpoint")
    func carbTargetIsDerived() {
        let targets = NutritionTargets.seeded

        #expect(targets.fatMidpointG == 65)
        // 2200 - (150 x 4) - (65 x 9) = 1015 kcal, at 4 kcal/g.
        #expect(targets.carbsG == 253.75)
    }

    @Test("a target that cannot pay for its own protein and fat yields no carbs")
    func carbTargetNeverNegative() {
        let impossible = NutritionTargets(kcal: 1400, proteinG: 300, proteinFloorG: 290,
                                          fatMinG: 60, fatMaxG: 70)
        #expect(impossible.carbsG == 0)
    }

    @Test("progress is a fraction of the goal and stops at full")
    func progressIsBounded() {
        let targets = NutritionTargets.seeded
        let totals = DayTotals(eaten: Macros(kcal: 1100, proteinG: 75, fatG: 140, carbsG: 0),
                               targets: targets)

        #expect(totals.kcalProgress == 0.5)
        #expect(totals.proteinProgress == 0.5)
        #expect(totals.fatProgress == 1)
        #expect(totals.carbsProgress == 0)
    }
}
