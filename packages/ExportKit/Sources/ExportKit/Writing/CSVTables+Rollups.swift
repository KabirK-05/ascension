import AscensionCore
import Foundation

extension CSVTables {
    /// `rollups.csv` — the whole day on one row.
    ///
    /// Nested groups keep their path as the column name (`nutrition.kcal`), so a leaf
    /// name means the same thing in both formats and a reader can map a column back to
    /// `export.json` without a lookup table. `workouts` and `topSets` are arrays and
    /// live in their own files, so the row carries their counts instead.
    static func rollups(_ rows: [DayRollup]) -> CSVTable {
        CSVTable(name: "rollups", columns: rollupColumns,
                 rows: rows.map(rollupRow))
    }

    private static let rollupColumns: [String] =
        ["date", "timezone", "updatedAt"]
        + ["nutrition.kcal", "nutrition.proteinG", "nutrition.fatG",
           "nutrition.carbsG", "nutrition.waterMl"]
        + ["activity.steps", "activity.activeEnergyKcal",
           "activity.exerciseMinutes", "activity.standHours"]
        + ["sleep.asleepMinutes", "sleep.inBedMinutes", "sleep.consistencySd7Minutes"]
        + ["vitals.restingHrBpm", "vitals.hrvSdnnMs", "vitals.vo2Max",
           "vitals.respiratoryRate", "vitals.spo2Pct"]
        + ["body.weightKg", "body.weightAvg7Kg", "body.rateKgPerWeek",
           "body.bodyFatPct", "body.waistCm"]
        + ["training.sessionPlanned", "training.sessionDone", "training.loadAu",
           "training.workoutCount", "training.topSetCount"]
        + ["checkIn.energy"]
        + MuscleGroup.allCases.map { "checkIn.soreness.\($0.rawValue)" }
        + ["readiness.score", "readiness.verdict", "readiness.reasons"]
        + ["wins.session", "wins.protein", "wins.steps", "wins.sleep", "wins.total"]

    private static func rollupRow(_ rollup: DayRollup) -> [CSVValue] {
        [.text(rollup.date.rawValue), .text(rollup.timezone),
         .text(rollup.updatedAt.rawValue)]
            + nutritionFields(rollup.nutrition)
            + activityFields(rollup.activity)
            + sleepFields(rollup.sleep)
            + vitalsFields(rollup.vitals)
            + bodyFields(rollup.body)
            + trainingFields(rollup.training)
            + checkInFields(rollup.checkIn)
            + readinessFields(rollup.readiness)
            + winsFields(rollup.wins)
    }

    private static func nutritionFields(_ group: NutritionRollup) -> [CSVValue] {
        [.optional(group.kcal), .optional(group.proteinG), .optional(group.fatG),
         .optional(group.carbsG), .optional(group.waterMl)]
    }

    private static func activityFields(_ group: ActivityRollup) -> [CSVValue] {
        [.optional(group.steps), .optional(group.activeEnergyKcal),
         .optional(group.exerciseMinutes), .optional(group.standHours)]
    }

    private static func sleepFields(_ group: SleepRollup) -> [CSVValue] {
        [.optional(group.asleepMinutes), .optional(group.inBedMinutes),
         .optional(group.consistencySd7Minutes)]
    }

    private static func vitalsFields(_ group: VitalsRollup) -> [CSVValue] {
        [.optional(group.restingHrBpm), .optional(group.hrvSdnnMs),
         .optional(group.vo2Max), .optional(group.respiratoryRate),
         .optional(group.spo2Pct)]
    }

    private static func bodyFields(_ group: BodyRollup) -> [CSVValue] {
        [.optional(group.weightKg), .optional(group.weightAvg7Kg),
         .optional(group.rateKgPerWeek), .optional(group.bodyFatPct),
         .optional(group.waistCm)]
    }

    private static func trainingFields(_ group: TrainingRollup) -> [CSVValue] {
        [.optional(group.sessionPlanned?.rawValue), .flag(group.sessionDone),
         .optional(group.loadAu), .integer(group.workouts.count),
         .integer(group.topSets.count)]
    }

    private static func checkInFields(_ group: CheckInRollup?) -> [CSVValue] {
        guard let group else {
            return [.null] + MuscleGroup.allCases.map { _ in CSVValue.null }
        }
        return [.integer(group.energy)]
            + MuscleGroup.allCases.map { .text(group.soreness.level(for: $0).rawValue) }
    }

    private static func readinessFields(_ group: ReadinessRollup?) -> [CSVValue] {
        guard let group else { return [.null, .null, .null] }
        return [.integer(group.score), .text(group.verdict.rawValue),
                .text(group.reasons.joined(separator: "; "))]
    }

    private static func winsFields(_ wins: Wins) -> [CSVValue] {
        [.flag(wins.session), .flag(wins.protein), .flag(wins.steps),
         .flag(wins.sleep), .integer(wins.total)]
    }
}
