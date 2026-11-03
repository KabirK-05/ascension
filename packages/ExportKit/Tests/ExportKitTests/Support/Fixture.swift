import AscensionCore
import Foundation

@testable import ExportKit

/// Invented data only. Spec §2 is a hard constraint, not a preference: chicken and eggs
/// are the only meats anywhere in here, no pork and no beef, and the one dairy drink is
/// milk with Bournvita. None of these numbers are the user's.
enum Fixture {
    static let timeZone = TimeZone(identifier: Seed.timezone) ?? .gmt

    /// The instant every fixture export is stamped with, so goldens are stable.
    static let exportedAt = Timestamp.literal("2026-11-30T06:00:00-05:00")

    static var environment: ExportEnvironment {
        ExportEnvironment(clock: FixedClock(exportedAt), timeZone: timeZone)
    }

    static let documents = ExportDocuments(goalSettings: Seed.goalSettings,
                                           program: Seed.program,
                                           flags: Seed.flags)

    /// Display names for the three exercises the spec §9.1 example abbreviates. The
    /// exercise library is ASC-8's; this is the map the app will hand over.
    static let exerciseNames = [
        "Goblet_Squat": "goblet squat",
        "DB_Bench_Press": "DB bench",
        "Romanian_Deadlift": "RDL"
    ]

    // MARK: - The spec §9.1 worked example

    /// The §9.1 journal example's day, field for field, so the renderer can be checked
    /// against the shape the spec fixes rather than against itself.
    static let workedExampleDate = CalendarDate.literal("2026-11-09")

    static var workedExampleRollup: DayRollup {
        DayRollup(
            date: workedExampleDate,
            timezone: Seed.timezone,
            updatedAt: Timestamp.literal("2026-11-09T23:05:00-05:00"),
            nutrition: NutritionRollup(kcal: 2180, proteinG: 148, fatG: 64,
                                       carbsG: 248, waterMl: 2400),
            activity: ActivityRollup(steps: 10_240, activeEnergyKcal: 612,
                                     exerciseMinutes: 54, standHours: 10),
            sleep: SleepRollup(asleepMinutes: 462, inBedMinutes: 495,
                               consistencySd7Minutes: 34),
            vitals: VitalsRollup(restingHrBpm: 58, hrvSdnnMs: 41, vo2Max: 44.2,
                                 respiratoryRate: 14.1, spo2Pct: 97),
            body: BodyRollup(weightKg: 73.6, weightAvg7Kg: 73.9, rateKgPerWeek: -0.4),
            training: TrainingRollup(
                sessionPlanned: .upperA,
                sessionDone: true,
                loadAu: 6120,
                workouts: [
                    WorkoutSummary(
                        healthKitId: "A1B2C3D4-0000-0000-0000-000000000001",
                        type: "traditionalStrengthTraining",
                        startedAt: Timestamp.literal("2026-11-09T19:04:00-05:00"),
                        endedAt: Timestamp.literal("2026-11-09T19:55:00-05:00"),
                        durationMinutes: 51,
                        activeEnergyKcal: 368,
                        hrAvgBpm: 120,
                        hrMaxBpm: 150,
                        timeInZonesMinutes: TimeInZonesMinutes(z1: 4, z2: 22, z3: 18,
                                                               z4: 6, z5: 1),
                        source: "Apple Workout")
                ],
                topSets: [
                    TopSet(exerciseId: "Goblet_Squat", weightKg: 24, reps: 12),
                    TopSet(exerciseId: "DB_Bench_Press", weightKg: 20, reps: 11),
                    TopSet(exerciseId: "Romanian_Deadlift", weightKg: 22, reps: 12)
                ]),
            checkIn: CheckInRollup(energy: 4,
                                   soreness: Soreness(back: .mild, quads: .sore,
                                                      hamstrings: .mild)),
            readiness: ReadinessRollup(score: 82, verdict: .trainAsPlanned,
                                       reasons: ["slept 7h42", "HRV near baseline"]),
            wins: Wins(session: true, protein: true, steps: true, sleep: true))
    }

    static var workedExampleMeals: [MealEntry] {
        [
            MealEntry(date: workedExampleDate, meal: .lunch,
                      foodItemId: nil, name: "chicken breast", grams: 200,
                      kcal: 330, proteinG: 48, fatG: 7, carbsG: 0),
            MealEntry(date: workedExampleDate, meal: .lunch,
                      foodItemId: nil, name: "rice", grams: 150,
                      kcal: 320, proteinG: 7, fatG: 1, carbsG: 69)
        ]
    }

    static var workedExampleSnapshot: ExportSnapshot {
        ExportSnapshot(rollups: [workedExampleRollup], documents: documents,
                       meals: workedExampleMeals, exerciseNames: exerciseNames)
    }
}
