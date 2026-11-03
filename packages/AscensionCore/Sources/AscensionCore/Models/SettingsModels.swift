import Foundation
import SwiftData

/// The user's targets and program cadence (spec §2, §7). One row; editable in Settings.
@Model
public final class GoalSettings {
    public var version: Int = 1
    public var updatedAt: String = ""
    public var updatedBy: ActorKind = ActorKind.device
    public var kcal: Int = 2200
    public var proteinG: Int = 150
    public var proteinMinG: Int = 140
    public var fatMinG: Int = 60
    public var fatMaxG: Int = 70
    public var steps: Int = 10_000
    public var sleepMinutes: Int = 450
    public var goalWeightKg: Double = 68
    public var heightCm: Int = 170
    /// The local day the current block starts, `YYYY-MM-DD`.
    public var programStartDate: String = ""
    public var deloadEveryWeeks: Int = 5
    public var timezone: String = ""
    public var excludedMeats: [String] = []
    public var allowedDairy: [String] = []
    public var noLiquidCalories: Bool = true

    public init(document: GoalSettingsDocument) {
        self.version = document.version
        self.updatedAt = document.updatedAt.rawValue
        self.updatedBy = document.updatedBy
        self.kcal = document.targets.kcal
        self.proteinG = document.targets.proteinG
        self.proteinMinG = document.targets.proteinMinG
        self.fatMinG = document.targets.fatMinG
        self.fatMaxG = document.targets.fatMaxG
        self.steps = document.targets.steps
        self.sleepMinutes = document.targets.sleepMinutes
        self.goalWeightKg = document.body.goalWeightKg
        self.heightCm = document.body.heightCm
        self.programStartDate = document.programStartDate.rawValue
        self.deloadEveryWeeks = document.deloadEveryWeeks
        self.timezone = document.timezone
        self.excludedMeats = document.dietaryRules.excludedMeats
        self.allowedDairy = document.dietaryRules.allowedDairy
        self.noLiquidCalories = document.dietaryRules.noLiquidCalories
    }

    /// The document form, which is what syncs and what Muse writes.
    public var document: GoalSettingsDocument? {
        guard let updatedAt = Timestamp(rawValue: updatedAt),
              let programStartDate = CalendarDate(rawValue: programStartDate) else {
            return nil
        }
        return GoalSettingsDocument(
            version: version,
            updatedAt: updatedAt,
            updatedBy: updatedBy,
            targets: GoalTargets(kcal: kcal, proteinG: proteinG, proteinMinG: proteinMinG,
                                 fatMinG: fatMinG, fatMaxG: fatMaxG, steps: steps,
                                 sleepMinutes: sleepMinutes),
            body: BodyGoals(goalWeightKg: goalWeightKg, heightCm: heightCm),
            programStartDate: programStartDate,
            deloadEveryWeeks: deloadEveryWeeks,
            timezone: timezone,
            dietaryRules: DietaryRules(excludedMeats: excludedMeats,
                                       allowedDairy: allowedDairy,
                                       noLiquidCalories: noLiquidCalories))
    }
}

/// What the last export wrote (spec §7, §9.1).
@Model
public final class ExportManifest {
    public var schemaVersion: Int = AscensionCoreModule.schemaVersion
    public var exportedAt: String = ""
    /// Rows written per entity, keyed by entity name.
    public var recordCounts: [String: Int] = [:]

    public init(schemaVersion: Int = AscensionCoreModule.schemaVersion,
                exportedAt: Timestamp, recordCounts: [String: Int]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt.rawValue
        self.recordCounts = recordCounts
    }
}
