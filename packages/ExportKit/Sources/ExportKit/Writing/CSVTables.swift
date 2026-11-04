import AscensionCore
import Foundation

/// The CSV side of an export: one table per entity, the same field names as
/// `export.json` and a column order that never shifts between runs.
public enum CSVTables {
    /// Every table an export writes, in the order it writes them.
    public static func all(for snapshot: ExportSnapshot) -> [CSVTable] {
        [
            rollups(snapshot.rollups),
            meals(snapshot.meals),
            topSets(snapshot.topSetRows),
            checkIns(snapshot.checkInRows),
            readiness(snapshot.readinessRows),
            workouts(snapshot.workoutRows),
            sleep(snapshot.sleepRows),
            weight(snapshot.weightRows)
        ]
    }

    static func meals(_ rows: [MealEntry]) -> CSVTable {
        CSVTable(
            name: "meals",
            columns: ["date", "meal", "foodItemId", "name", "grams",
                      "kcal", "proteinG", "fatG", "carbsG"],
            rows: rows.map { row in
                [.text(row.date.rawValue), .text(row.meal.rawValue),
                 .optional(row.foodItemId), .text(row.name), .number(row.grams),
                 .number(row.kcal), .number(row.proteinG),
                 .number(row.fatG), .number(row.carbsG)]
            })
    }

    static func topSets(_ rows: [TopSetRow]) -> CSVTable {
        CSVTable(
            name: "topSets",
            columns: ["date", "exerciseId", "weightKg", "reps"],
            rows: rows.map { row in
                [.text(row.date.rawValue), .text(row.exerciseId),
                 .number(row.weightKg), .integer(row.reps)]
            })
    }

    static func checkIns(_ rows: [CheckInRow]) -> CSVTable {
        CSVTable(
            name: "checkIns",
            columns: ["date", "energy"] + MuscleGroup.allCases.map { "soreness.\($0.rawValue)" },
            rows: rows.map { row in
                [.text(row.date.rawValue), .integer(row.energy)]
                    + MuscleGroup.allCases.map { .text(row.soreness.level(for: $0).rawValue) }
            })
    }

    static func readiness(_ rows: [ReadinessRow]) -> CSVTable {
        CSVTable(
            name: "readiness",
            columns: ["date", "score", "verdict", "reasons"],
            rows: rows.map { row in
                // `reasons` is an array in JSON; one field holding a `; `-joined list
                // keeps the row rectangular, which is the point of the CSV mirror.
                [.text(row.date.rawValue), .integer(row.score),
                 .text(row.verdict.rawValue), .text(row.reasons.joined(separator: "; "))]
            })
    }

    static func workouts(_ rows: [WorkoutRow]) -> CSVTable {
        CSVTable(
            name: "workouts",
            columns: ["date", "healthKitId", "type", "startedAt", "endedAt",
                      "durationMinutes", "activeEnergyKcal", "hrAvgBpm", "hrMaxBpm",
                      "timeInZonesMinutes.z1", "timeInZonesMinutes.z2",
                      "timeInZonesMinutes.z3", "timeInZonesMinutes.z4",
                      "timeInZonesMinutes.z5", "source"],
            rows: rows.map { row in
                let zones = row.timeInZonesMinutes
                return [.text(row.date.rawValue), .text(row.healthKitId), .text(row.type),
                        .text(row.startedAt.rawValue), .text(row.endedAt.rawValue),
                        .integer(row.durationMinutes), .optional(row.activeEnergyKcal),
                        .optional(row.hrAvgBpm), .optional(row.hrMaxBpm),
                        .number(zones.z1), .number(zones.z2), .number(zones.z3),
                        .number(zones.z4), .number(zones.z5), .text(row.source)]
            })
    }

    static func sleep(_ rows: [SleepRow]) -> CSVTable {
        CSVTable(
            name: "sleep",
            columns: ["date", "asleepMinutes", "inBedMinutes", "consistencySd7Minutes"],
            rows: rows.map { row in
                [.text(row.date.rawValue), .optional(row.asleepMinutes),
                 .optional(row.inBedMinutes), .optional(row.consistencySd7Minutes)]
            })
    }

    static func weight(_ rows: [WeightRow]) -> CSVTable {
        CSVTable(
            name: "weight",
            columns: ["date", "weightKg", "weightAvg7Kg", "rateKgPerWeek",
                      "bodyFatPct", "waistCm"],
            rows: rows.map { row in
                [.text(row.date.rawValue), .optional(row.weightKg),
                 .optional(row.weightAvg7Kg), .optional(row.rateKgPerWeek),
                 .optional(row.bodyFatPct), .optional(row.waistCm)]
            })
    }
}
