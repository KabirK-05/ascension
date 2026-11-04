import Foundation
import Testing

@testable import AscensionCore

@Suite("wins follow the §1 table exactly")
struct WinsTests {
    static let goals = Seed.goalSettings

    @Test("a day that hits every target wins all four")
    func allFourWins() {
        let rollup = Fixture.rollup(
            nutrition: NutritionRollup(proteinG: 148),
            activity: ActivityRollup(steps: 10_240),
            sleep: SleepRollup(asleepMinutes: 462),
            training: TrainingRollup(sessionPlanned: .upperA, sessionDone: true))

        let wins = WinsCalculator.wins(for: rollup, goals: Self.goals)
        #expect(wins == Wins(session: true, protein: true, steps: true, sleep: true))
        #expect(wins.total == 4)
    }

    @Test("a day that hits nothing wins none")
    func noWins() {
        let rollup = Fixture.rollup(
            nutrition: NutritionRollup(proteinG: 90),
            activity: ActivityRollup(steps: 4_000),
            sleep: SleepRollup(asleepMinutes: 380),
            training: TrainingRollup(sessionPlanned: .upperA, sessionDone: false))

        let wins = WinsCalculator.wins(for: rollup, goals: Self.goals)
        #expect(wins.total == 0)
    }

    @Test("a planned rest day with no workout is a session win")
    func restDayWithoutWorkoutWins() {
        let rollup = Fixture.rollup(
            training: TrainingRollup(sessionPlanned: .rest, sessionDone: false))

        #expect(WinsCalculator.wins(for: rollup, goals: Self.goals).session)
    }

    @Test("a planned rest day with a workout is not a session win")
    func restDayWithWorkoutDoesNotWin() {
        let workout = WorkoutSummary(
            healthKitId: "A1B2C3D4-0000-0000-0000-000000000002",
            type: "walking",
            startedAt: Timestamp.literal("2026-11-09T18:00:00-05:00"),
            endedAt: Timestamp.literal("2026-11-09T18:30:00-05:00"),
            durationMinutes: 30,
            source: "Apple Workout")
        let rollup = Fixture.rollup(
            training: TrainingRollup(sessionPlanned: .rest, sessionDone: false,
                                     workouts: [workout]))

        #expect(!WinsCalculator.wins(for: rollup, goals: Self.goals).session)
    }

    @Test("a completed session wins even on a rest day that also logged a workout")
    func sessionDoneAlwaysWins() {
        let workout = WorkoutSummary(
            healthKitId: "A1B2C3D4-0000-0000-0000-000000000003",
            type: "traditionalStrengthTraining",
            startedAt: Timestamp.literal("2026-11-09T19:00:00-05:00"),
            endedAt: Timestamp.literal("2026-11-09T19:45:00-05:00"),
            durationMinutes: 45,
            source: "Apple Workout")
        let rollup = Fixture.rollup(
            training: TrainingRollup(sessionPlanned: .rest, sessionDone: true,
                                     workouts: [workout]))

        #expect(WinsCalculator.wins(for: rollup, goals: Self.goals).session)
    }

    @Test("a win against a null measurement is false, never true")
    func nullMeasurementsNeverWin() {
        let rollup = Fixture.rollup(
            training: TrainingRollup(sessionPlanned: .upperA, sessionDone: false))

        let wins = WinsCalculator.wins(for: rollup, goals: Self.goals)
        #expect(!wins.protein)
        #expect(!wins.steps)
        #expect(!wins.sleep)
        #expect(!wins.session)
        #expect(wins.total == 0)
    }

    @Test("an unplanned day with no measurements still loses every win")
    func unplannedEmptyDayLosesEverything() {
        let rollup = Fixture.rollup()
        #expect(WinsCalculator.wins(for: rollup, goals: Self.goals).total == 0)
    }

    @Test("each target wins at exactly its threshold, and loses one below")
    func thresholdsAreInclusive() {
        let targets = Self.goals.targets
        let atTarget = Fixture.rollup(
            nutrition: NutritionRollup(proteinG: Double(targets.proteinMinG)),
            activity: ActivityRollup(steps: targets.steps),
            sleep: SleepRollup(asleepMinutes: targets.sleepMinutes))
        #expect(WinsCalculator.wins(for: atTarget, goals: Self.goals).total == 3)

        let justBelow = Fixture.rollup(
            nutrition: NutritionRollup(proteinG: Double(targets.proteinMinG) - 0.1),
            activity: ActivityRollup(steps: targets.steps - 1),
            sleep: SleepRollup(asleepMinutes: targets.sleepMinutes - 1))
        #expect(WinsCalculator.wins(for: justBelow, goals: Self.goals).total == 0)
    }

    @Test("protein is judged against the 140 g floor, not the 150 g target")
    func proteinUsesTheFloor() {
        let rollup = Fixture.rollup(nutrition: NutritionRollup(proteinG: 142))
        #expect(WinsCalculator.wins(for: rollup, goals: Self.goals).protein)
    }

    @Test("recomputing wins overwrites whatever the rollup carried")
    func withComputedWinsOverwrites() {
        var rollup = Fixture.rollup(activity: ActivityRollup(steps: 12_000))
        rollup.wins = Wins(session: true, protein: true, steps: true, sleep: true)

        let corrected = rollup.withComputedWins(goals: Self.goals)
        #expect(corrected.wins == Wins(session: false, protein: false,
                                       steps: true, sleep: false))
        #expect(corrected.wins.total == 1)
    }

    @Test("total can only ever be the count of the flags")
    func totalIsAlwaysTheCount() {
        for flags in 0..<16 {
            let wins = Wins(session: flags & 1 != 0, protein: flags & 2 != 0,
                            steps: flags & 4 != 0, sleep: flags & 8 != 0)
            #expect(wins.total == [wins.session, wins.protein, wins.steps, wins.sleep]
                .count { $0 })
        }
    }
}

@Suite("loadAu is the contract's formula")
struct LoadTests {
    @Test("load sums duration times the heart-rate intensity factor")
    func loadSumsIntensity() throws {
        let workout = WorkoutSummary(
            healthKitId: "A1B2C3D4-0000-0000-0000-000000000004",
            type: "traditionalStrengthTraining",
            startedAt: Timestamp.literal("2026-11-03T19:04:00-05:00"),
            endedAt: Timestamp.literal("2026-11-03T19:55:00-05:00"),
            durationMinutes: 50,
            hrAvgBpm: 116,
            source: "Apple Workout")

        let load = try #require(TrainingRollup.loadAu(workouts: [workout], restingHrBpm: 58))
        #expect(load == 100)
    }

    @Test("load is nil when nothing measured can feed the formula")
    func loadIsNilWithoutInputs() {
        #expect(TrainingRollup.loadAu(workouts: [], restingHrBpm: 58) == nil)
    }
}
