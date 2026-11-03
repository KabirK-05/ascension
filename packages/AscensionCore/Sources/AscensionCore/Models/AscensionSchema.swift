import Foundation
import SwiftData

/// Every app-owned entity (spec §7), in one place so the app and the tests open the
/// same store.
public enum AscensionSchema {
    public static let models: [any PersistentModel.Type] = [
        Program.self,
        ProgramDay.self,
        SessionTemplate.self,
        SessionExercise.self,
        Exercise.self,
        FoodItem.self,
        MealLog.self,
        TopSetLog.self,
        CheckIn.self,
        ReadinessSnapshot.self,
        GoalSettings.self,
        ExportManifest.self
    ]

    public static var schema: Schema { Schema(models) }
}
