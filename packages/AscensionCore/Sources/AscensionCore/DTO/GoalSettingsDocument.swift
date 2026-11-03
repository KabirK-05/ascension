import Foundation

/// Daily targets (spec §2). All integers, all in the fixed units.
public struct GoalTargets: Codable, Hashable, Sendable {
    public var kcal: Int
    public var proteinG: Int
    public var proteinMinG: Int
    public var fatMinG: Int
    public var fatMaxG: Int
    public var steps: Int
    public var sleepMinutes: Int

    public init(kcal: Int, proteinG: Int, proteinMinG: Int, fatMinG: Int,
                fatMaxG: Int, steps: Int, sleepMinutes: Int) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.proteinMinG = proteinMinG
        self.fatMinG = fatMinG
        self.fatMaxG = fatMaxG
        self.steps = steps
        self.sleepMinutes = sleepMinutes
    }
}

/// Where the body is headed.
public struct BodyGoals: Codable, Hashable, Sendable {
    public var goalWeightKg: Double
    public var heightCm: Int

    public init(goalWeightKg: Double, heightCm: Int) {
        self.goalWeightKg = goalWeightKg
        self.heightCm = heightCm
    }
}

/// Hard dietary constraints (spec §2), not preferences.
public struct DietaryRules: Codable, Hashable, Sendable {
    /// Meats that may never appear in a suggestion, seed or sample. Always contains
    /// `pork` and `beef`: chicken and eggs are the only meats.
    public var excludedMeats: [String]
    public var allowedDairy: [String]
    public var noLiquidCalories: Bool

    public init(excludedMeats: [String], allowedDairy: [String], noLiquidCalories: Bool) {
        self.excludedMeats = excludedMeats
        self.allowedDairy = allowedDairy
        self.noLiquidCalories = noLiquidCalories
    }
}

/// The `goalSettings` document (`docs/EXPORT_SCHEMA.md` §2.1). `version` increments on
/// every write; concurrency is `If-Match: <version>`.
public struct GoalSettingsDocument: Codable, Hashable, Sendable {
    public var version: Int
    public var updatedAt: Timestamp
    public var updatedBy: ActorKind
    public var targets: GoalTargets
    public var body: BodyGoals
    public var programStartDate: CalendarDate
    public var deloadEveryWeeks: Int
    public var timezone: String
    public var dietaryRules: DietaryRules

    public init(version: Int, updatedAt: Timestamp, updatedBy: ActorKind,
                targets: GoalTargets, body: BodyGoals, programStartDate: CalendarDate,
                deloadEveryWeeks: Int, timezone: String, dietaryRules: DietaryRules) {
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.targets = targets
        self.body = body
        self.programStartDate = programStartDate
        self.deloadEveryWeeks = deloadEveryWeeks
        self.timezone = timezone
        self.dietaryRules = dietaryRules
    }
}

extension GoalSettingsDocument {
    public static let kcalRange = 1400...4000
    public static let absoluteFatFloorG = 60
    public static let requiredExcludedMeats = ["pork", "beef"]

    /// The invariants the contract rejects a write for, rather than clamping silently.
    public func validate() throws {
        guard targets.fatMinG >= Self.absoluteFatFloorG else {
            throw DomainValidationError.fatFloorBelowMinimum(targets.fatMinG)
        }
        guard targets.fatMinG <= targets.fatMaxG else {
            throw DomainValidationError.fatRangeInverted(min: targets.fatMinG,
                                                         max: targets.fatMaxG)
        }
        guard Self.kcalRange.contains(targets.kcal) else {
            throw DomainValidationError.calorieTargetOutOfRange(targets.kcal)
        }
        guard targets.proteinMinG <= targets.proteinG else {
            throw DomainValidationError.proteinFloorAboveTarget(min: targets.proteinMinG,
                                                                target: targets.proteinG)
        }
        let excluded = Set(dietaryRules.excludedMeats.map { $0.lowercased() })
        let missing = Self.requiredExcludedMeats.filter { !excluded.contains($0) }
        guard missing.isEmpty else {
            throw DomainValidationError.excludedMeatsIncomplete(missing: missing)
        }
    }
}
