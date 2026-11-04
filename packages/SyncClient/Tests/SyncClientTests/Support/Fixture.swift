import AscensionCore
import Foundation

@testable import SyncClient

/// The fixtures every test builds from.
///
/// Fully populated on purpose: the ingest golden is diffed against `edge/src/contract.ts`,
/// and a field left `nil` in the fixture is a field the contract check cannot see.
enum Fixture {
    static let timezone = Seed.timezone

    // Force unwrapping is a lint error in this repo, so the two literals that cannot fail
    // at authoring time trap with the offending value named instead.
    static let origin: SyncEndpoint = {
        guard let endpoint = SyncEndpoint(origin: "https://edge.example.test") else {
            preconditionFailure("malformed test origin")
        }
        return endpoint
    }()

    static var clock: FixedClock {
        let stamp = Timestamp.literal("2026-11-03T23:05:00-05:00")
        guard let clock = FixedClock(timestamp: stamp, timeZoneIdentifier: timezone) else {
            preconditionFailure("malformed test clock: \(stamp.rawValue)")
        }
        return clock
    }

    static func session(_ transport: FakeTransport,
                        token: String? = "device-token-for-tests",
                        policy: RetryPolicy = .none,
                        sleeper: any Sleeper = RecordingSleeper()) -> SyncSession {
        SyncSession(transport: transport, tokens: InMemoryDeviceTokenStore(token: token),
                    policy: policy, sleeper: sleeper)
    }

    static var goals: GoalSettingsDocument {
        GoalSettingsDocument(
            version: 7,
            updatedAt: Timestamp.literal("2026-11-03T18:00:00-05:00"),
            updatedBy: .muse,
            targets: GoalTargets(kcal: 2200, proteinG: 150, proteinMinG: 140, fatMinG: 60,
                                 fatMaxG: 70, steps: 10_000, sleepMinutes: 450),
            body: BodyGoals(goalWeightKg: 68.0, heightCm: 170),
            programStartDate: Seed.programStartDate,
            deloadEveryWeeks: 5,
            timezone: timezone,
            dietaryRules: DietaryRules(excludedMeats: ["pork", "beef"],
                                       allowedDairy: ["milk_bournvita"],
                                       noLiquidCalories: true))
    }

    /// HealthKit's half of a day, as `HealthBridge`'s `snapshot.applied(to:)` leaves it.
    static func measured(date: String = "2026-11-03") -> DayRollup {
        DayRollup(
            date: CalendarDate.literal(date),
            timezone: timezone,
            updatedAt: Timestamp.literal("2026-11-03T06:00:00-05:00"),
            nutrition: NutritionRollup(waterMl: 2400),
            activity: ActivityRollup(steps: 10_240, activeEnergyKcal: 612,
                                     exerciseMinutes: 54, standHours: 10),
            sleep: SleepRollup(asleepMinutes: 462, inBedMinutes: 495),
            vitals: VitalsRollup(restingHrBpm: 58, hrvSdnnMs: 41, vo2Max: 44.2,
                                 respiratoryRate: 14.1, spo2Pct: 97),
            body: BodyRollup(weightKg: 73.6, bodyFatPct: nil, waistCm: nil),
            training: TrainingRollup(loadAu: 105.5, workouts: [workout], topSets: []),
            wins: Wins(session: false, protein: false, steps: false, sleep: false))
    }

    static var workout: WorkoutSummary {
        WorkoutSummary(healthKitId: "A1B2C3D4-0000-0000-0000-000000000001",
                       type: "traditionalStrengthTraining",
                       startedAt: Timestamp.literal("2026-11-03T19:04:00-05:00"),
                       endedAt: Timestamp.literal("2026-11-03T19:55:00-05:00"),
                       durationMinutes: 51, activeEnergyKcal: 368, hrAvgBpm: 120, hrMaxBpm: 150,
                       timeInZonesMinutes: TimeInZonesMinutes(z1: 4, z2: 22, z3: 18, z4: 6, z5: 1),
                       source: "Apple Workout")
    }

    /// The device's half: meals, plan, top sets, check-in, readiness, engine trends.
    static var deviceDay: DeviceDay {
        DeviceDay(
            meals: [
                LoggedMeal(id: "01JC8X9Y2K3M4N5P6Q7R8S9T01", slot: .breakfast,
                           loggedAt: Timestamp.literal("2026-11-03T08:10:00-05:00"),
                           kcal: 620, proteinG: 44, fatG: 18, carbsG: 70),
                LoggedMeal(id: "01JC8X9Y2K3M4N5P6Q7R8S9T02", slot: .dinner,
                           loggedAt: Timestamp.literal("2026-11-03T19:30:00-05:00"),
                           kcal: 1560, proteinG: 104, fatG: 46, carbsG: 178)
            ],
            sessionPlanned: .upperA,
            sessionDone: true,
            topSets: [TopSet(exerciseId: "Goblet_Squat", weightKg: 24.0, reps: 12),
                      TopSet(exerciseId: "DB_Bench_Press", weightKg: 20.0, reps: 11)],
            checkIn: CheckInRollup(energy: 4, soreness: Soreness(back: .mild, quads: .sore,
                                                                 hamstrings: .mild)),
            readiness: ReadinessRollup(score: 82, verdict: .trainAsPlanned,
                                       reasons: ["slept 7h42", "HRV near baseline"]),
            trends: TrendOverlay(weightAvg7Kg: 73.9, rateKgPerWeek: -0.4,
                                 consistencySd7Minutes: 34))
    }

    /// The rollup the client actually pushes: both halves, `wins` from `WinsCalculator`.
    static var rollup: DayRollup {
        RollupAssembler.assemble(measured: measured(), device: deviceDay, goals: goals,
                                 clock: clock)
    }

    static func rollup(date: String, updatedAt: String? = nil) -> DayRollup {
        var copy = RollupAssembler.assemble(measured: measured(date: date), device: deviceDay,
                                            goals: goals, clock: clock)
        if let updatedAt { copy.updatedAt = Timestamp.literal(updatedAt) }
        return copy
    }

    static let ingestReceipt = """
        {"schemaVersion":1,"accepted":1,"dates":["2026-11-03"],\
        "ingestedAt":"2026-11-04T04:05:00.000Z"}
        """
}
