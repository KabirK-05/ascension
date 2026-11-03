import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Rollup assembly")
struct RollupAssemblyTests {
    @Test("wins come from AscensionCore's WinsCalculator, not from a second implementation")
    func winsDelegateToCore() {
        let rollup = Fixture.rollup
        #expect(rollup.wins == WinsCalculator.wins(for: rollup, goals: Fixture.goals))
        // 148 g protein ≥ 140, 10,240 steps ≥ 10,000, 462 min ≥ 450, session done.
        #expect(rollup.wins.total == 4)
    }

    @Test("the device's half overlays HealthKit's, and HealthKit's half survives")
    func overlayKeepsBothHalves() {
        let rollup = Fixture.rollup
        #expect(rollup.nutrition.kcal == 2180)
        #expect(rollup.nutrition.proteinG == 148)
        #expect(rollup.training.sessionPlanned == .upperA)
        #expect(rollup.training.topSets.count == 2)
        #expect(rollup.checkIn?.energy == 4)
        #expect(rollup.readiness?.score == 82)
        // HealthKit's, untouched.
        #expect(rollup.activity.steps == 10_240)
        #expect(rollup.vitals.hrvSdnnMs == 41)
        #expect(rollup.training.workouts.count == 1)
        #expect(rollup.training.loadAu == 105.5)
    }

    @Test("the engines' rolling numbers land where HealthKit leaves gaps")
    func trendsFillTheRollingFields() {
        let rollup = Fixture.rollup
        #expect(rollup.body.weightAvg7Kg == 73.9)
        #expect(rollup.body.rateKgPerWeek == -0.4)
        #expect(rollup.sleep.consistencySd7Minutes == 34)
    }

    @Test("a macro no meal carried stays null — not measured is not zero")
    func unmeasuredMacrosStayNull() {
        let meal = LoggedMeal(id: "01JC8X9Y2K3M4N5P6Q7R8S9T01", slot: .snack,
                              loggedAt: Timestamp.literal("2026-11-03T16:00:00-05:00"),
                              kcal: 180)
        let device = DeviceDay(meals: [meal])
        let rollup = RollupAssembler.assemble(measured: Fixture.measured(), device: device,
                                              goals: Fixture.goals, clock: Fixture.clock)
        #expect(rollup.nutrition.kcal == 180)
        #expect(rollup.nutrition.proteinG == nil)
        #expect(rollup.wins.protein == false)
    }

    @Test("water prefers HealthKit's mirror, which already includes what this app wrote")
    func waterPrefersTheMirror() {
        let logged = LoggedMeal(id: "01JC8X9Y2K3M4N5P6Q7R8S9T01", slot: .snack,
                                loggedAt: Timestamp.literal("2026-11-03T16:00:00-05:00"),
                                waterMl: 250)
        let rollup = RollupAssembler.assemble(measured: Fixture.measured(),
                                              device: DeviceDay(meals: [logged]),
                                              goals: Fixture.goals, clock: Fixture.clock)
        #expect(rollup.nutrition.waterMl == 2400)

        var dry = Fixture.measured()
        dry.nutrition.waterMl = nil
        let fallback = RollupAssembler.assemble(measured: dry, device: DeviceDay(meals: [logged]),
                                                goals: Fixture.goals, clock: Fixture.clock)
        #expect(fallback.nutrition.waterMl == 250)
    }

    @Test("assembly is deterministic: the same inputs give the same bytes")
    func assemblyIsDeterministic() throws {
        let first = try SyncCoding.encoder().encode(Fixture.rollup)
        let second = try SyncCoding.encoder().encode(Fixture.rollup)
        #expect(first == second)
        #expect(Fixture.rollup.updatedAt.rawValue == "2026-11-03T23:05:00-05:00")
    }

    @Test("a rest day with no workout is still a session win")
    func restDayCountsAsASession() {
        var measured = Fixture.measured()
        measured.training.workouts = []
        var device = Fixture.deviceDay
        device.sessionPlanned = .rest
        device.sessionDone = false
        let rollup = RollupAssembler.assemble(measured: measured, device: device,
                                              goals: Fixture.goals, clock: Fixture.clock)
        #expect(rollup.wins.session)
    }
}
