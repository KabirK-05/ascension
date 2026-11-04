import Foundation
import SwiftData

extension Seed {
    /// Writes the seed into an empty store: targets, the current program, the staples
    /// and the program exercises.
    ///
    /// Idempotent by omission — it inserts nothing when the store already holds goal
    /// settings, so a relaunch never duplicates the seed or overwrites an edit.
    @MainActor
    public static func install(into context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<GoalSettings>())
        guard existing.isEmpty else { return }

        try goalSettings.validate()
        try program.validate()

        context.insert(GoalSettings(document: goalSettings))
        context.insert(Program(document: program, isActive: true))
        for food in stapleFoods {
            context.insert(FoodItem(dto: food))
        }
        for exercise in programExercises {
            context.insert(Exercise(dto: exercise))
        }
        try context.save()
    }
}
