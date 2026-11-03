import AscensionCore
import Foundation
import Testing

@testable import HealthBridge

@Suite("the plan sent to the Watch")
struct SessionPlanTests {
    private let program = Seed.program
    private let zones = HeartRateZones.forAge(25)

    private func makePlan(_ kind: SessionKind, zones: HeartRateZones? = nil) -> SessionPlan? {
        guard let template = program.sessions[kind] else { return nil }
        return SessionPlanBuilder.plan(kind: kind, template: template,
                                       finisher: program.finisher, zones: zones)
    }

    @Test("a rest day has nothing to send")
    func restDaySendsNothing() {
        let template = SessionTemplateEntry(name: "Rest", exercises: [])
        #expect(SessionPlanBuilder.plan(kind: .rest, template: template,
                                        finisher: program.finisher) == nil)
    }

    @Test("a lifting session is one open-goal block per exercise, repeated for its sets")
    func liftingBlocksMatchTheTemplate() throws {
        let plan = try #require(makePlan(.upperB))
        #expect(plan.activity == .traditionalStrengthTraining)
        #expect(plan.displayName == "Upper B")
        // Upper B carries no finisher slot, so every block is a lift.
        #expect(plan.blocks.count == 4)
        #expect(plan.blocks.allSatisfy { $0.steps.allSatisfy { $0.goal == .open } })
        #expect(plan.blocks.allSatisfy { $0.iterations == 3 })
        #expect(plan.blocks.allSatisfy { $0.steps.allSatisfy { $0.heartRate == nil } })
    }

    @Test("a day with a finisher slot gets a timed Zone 2 interval after the lifts")
    func finisherBecomesATimedInterval() throws {
        let plan = try #require(makePlan(.upperA, zones: zones))
        // Four lifts plus the finisher; the finisher slot itself is not a lift block.
        #expect(plan.blocks.count == 5)
        let finisher = try #require(plan.blocks.last?.steps.first)
        #expect(finisher.goal == .minutes(15))
        #expect(finisher.displayName == "Incline walk")
        #expect(finisher.heartRate == SessionPlanBuilder.zone2Target(zones))
    }

    @Test("exercise names reach the Watch when the caller supplies them")
    func namesAreUsedWhenKnown() throws {
        let template = try #require(program.sessions[.lowerA])
        let plan = try #require(SessionPlanBuilder.plan(
            kind: .lowerA, template: template, finisher: program.finisher,
            exerciseNames: [SeedExerciseId.gobletSquat: "Goblet squat"]))
        #expect(plan.blocks.first?.steps.first?.displayName == "Goblet squat")
        // An id with no name falls back to the id rather than to an empty step.
        #expect(plan.blocks.dropFirst().first?.steps.first?.displayName
            == SeedExerciseId.dbRomanianDeadlift)
    }

    @Test("a Zone 2 session is a timed walk with a heart-rate target")
    func zone2IsAWalkWithATarget() throws {
        let historical = Seed.historicalProgram
        let template = try #require(historical.sessions[.zone2])
        let plan = try #require(SessionPlanBuilder.plan(
            kind: .zone2, template: template, finisher: historical.finisher, zones: zones))
        #expect(plan.activity == .walking)
        #expect(plan.blocks.count == 1)
        let step = try #require(plan.blocks.first?.steps.first)
        #expect(step.goal == .minutes(15))
        #expect(step.heartRate != nil)
    }

    @Test("Zone 2 is this app's own bpm bounds when it knows them, and a zone number when it does not")
    func zone2TargetPrefersOurOwnBounds() {
        #expect(SessionPlanBuilder.zone2Target(nil) == .zone(2))
        guard case .bpmRange(let range) = SessionPlanBuilder.zone2Target(zones) else {
            Issue.record("expected a bpm range when the zones are known")
            return
        }
        #expect(range.lowerBound == Int(zones.lowerBounds[1].rounded()))
        #expect(range.upperBound == Int(zones.lowerBounds[2].rounded()) - 1)
        #expect(range.lowerBound < range.upperBound)
    }

    @Test("a block never repeats fewer than once, whatever the template says")
    func iterationsAreAtLeastOne() {
        #expect(SessionPlanBlock(steps: [SessionPlanStep()], iterations: 0).iterations == 1)
    }

    @Test("where WorkoutKit is absent, scheduling refuses rather than pretending")
    func unavailableSchedulerRefuses() async {
        let scheduler = UnavailableSessionScheduler()
        #expect(scheduler.isSupported == false)
        #expect(await scheduler.requestAuthorization() == .unavailable)
        await #expect(throws: SessionSchedulingError.schedulingUnavailable) {
            try await scheduler.schedule(
                SessionPlan(displayName: "Upper A", activity: .traditionalStrengthTraining,
                            blocks: []),
                at: Date())
        }
    }
}
