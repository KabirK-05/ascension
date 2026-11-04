import Foundation

extension Seed {
    /// Targets from spec §2: 2,200 kcal, 150 g protein on a 140 g floor, fat 60–70 g,
    /// 10,000 steps, 7.5 h sleep, goal weight 68 kg.
    public static let goalSettings = GoalSettingsDocument(
        version: 1,
        updatedAt: seededAt,
        updatedBy: .device,
        targets: GoalTargets(
            kcal: 2200,
            proteinG: 150,
            proteinMinG: 140,
            fatMinG: 60,
            fatMaxG: 70,
            steps: 10_000,
            sleepMinutes: 450),
        body: BodyGoals(goalWeightKg: 68.0, heightCm: 170),
        programStartDate: programStartDate,
        deloadEveryWeeks: 5,
        timezone: timezone,
        dietaryRules: DietaryRules(
            excludedMeats: ["pork", "beef"],
            allowedDairy: ["milk_bournvita"],
            noLiquidCalories: true))
}
