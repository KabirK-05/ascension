import AscensionCore
import Foundation
import Testing

@testable import FeatureTrain

@Suite("the rir2 progression rule")
struct ProgressionTests {
    private let settings = ProgressionSettings(rule: .rir2, incrementKg: 2.5)
    private let bench = SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.dbBenchPress)

    private func logged(_ weight: Double, _ reps: Int,
                        on raw: String = "2026-11-02") -> LoggedTopSet {
        LoggedTopSet(date: Fixture.date(raw), exerciseId: SeedExerciseId.dbBenchPress,
                     weightKg: weight, reps: reps)
    }

    @Test("the spec's own example: 20 kg × 11 in a 10–12 range becomes 22.5 kg")
    func specExample() {
        let target = Progression.target(for: bench, history: [logged(20, 11)], settings: settings)
        #expect(target.advancing)
        #expect(target.targetWeightKg == 22.5)
        #expect(target.last?.reps == 11)
    }

    @Test("two reps in reserve must clear the top of the range, not merely reach it")
    func reserveMustClearTheRange() {
        // 10 reps plus two in reserve is 12, which is the top of the range and not past
        // it: the load stays where it is for another session.
        #expect(Progression.advances(reps: 10, repsHigh: 12, rule: .rir2) == false)
        #expect(Progression.advances(reps: 11, repsHigh: 12, rule: .rir2))
        #expect(Progression.advances(reps: 12, repsHigh: 12, rule: .rir2))
    }

    @Test("a held load keeps its weight rather than losing it")
    func holdingKeepsTheLoad() {
        let target = Progression.target(for: bench, history: [logged(20, 9)], settings: settings)
        #expect(target.advancing == false)
        #expect(target.targetWeightKg == 20)
    }

    @Test("the most recent log is the one that decides, whatever order they arrive in")
    func theLatestLogDecides() {
        let history = [logged(25, 12, on: "2026-11-09"), logged(20, 8, on: "2026-11-02")]
        let target = Progression.target(for: bench, history: history, settings: settings)
        #expect(target.last?.weightKg == 25)
        #expect(target.targetWeightKg == 27.5)
    }

    @Test("an exercise never logged has no target to offer")
    func noHistoryMeansNoTarget() {
        let target = Progression.target(for: bench, history: [], settings: settings)
        #expect(target.last == nil)
        #expect(target.targetWeightKg == nil)
        #expect(target.advancing == false)
    }

    @Test("a plank or a carry has no rep range, so its load is never advanced by the rule")
    func holdsNeverAdvance() {
        let plank = SessionExerciseEntry(order: 4, exerciseId: SeedExerciseId.plank,
                                         sets: 3, repsLow: 1, repsHigh: 1)
        let history = [LoggedTopSet(date: Fixture.date("2026-11-02"),
                                    exerciseId: SeedExerciseId.plank, weightKg: 10, reps: 1)]
        let target = Progression.target(for: plank, history: history, settings: settings)
        #expect(target.advancing == false)
        #expect(target.targetWeightKg == 10)
    }

    @Test("the finisher is not a top set, so the session's loggable slots exclude it")
    func theFinisherIsNotLogged() throws {
        let upperA = try #require(Seed.program.sessions[.upperA])
        let slots = Progression.loggableSlots(in: upperA)
        #expect(upperA.exercises.count == 5)
        #expect(slots.count == 4)
        #expect(slots.contains { $0.exerciseId == SeedExerciseId.inclineTreadmillWalk } == false)
        #expect(slots.map(\.order) == [1, 2, 3, 4])
    }

    @Test("a session's targets come back in program order")
    func targetsFollowProgramOrder() throws {
        let upperA = try #require(Seed.program.sessions[.upperA])
        let targets = Progression.targets(for: upperA, history: [logged(20, 11)],
                                          settings: settings)
        #expect(targets.first?.exerciseId == SeedExerciseId.dbBenchPress)
        #expect(targets.first?.targetWeightKg == 22.5)
        #expect(targets.dropFirst().allSatisfy { $0.targetWeightKg == nil })
    }
}
