import AscensionCore
import Foundation
import Testing

@testable import FeatureTrain

@Suite("the post-workout debrief")
struct DebriefTests {
    private let monday = Fixture.date("2026-11-02")
    private let thursday = Fixture.date("2026-11-05")

    @Test("the comparison is against the last session of the same type")
    func previousIsSameTypeOnly() throws {
        let earlier = Fixture.session("lift-1", on: monday, hour: 18, minutes: 42,
                                      energy: 280, hrAvg: 123)
        let walk = Fixture.session("walk", type: "walking", on: monday, hour: 19, minutes: 15)
        let latest = Fixture.session("lift-2", on: thursday, hour: 18, minutes: 48,
                                     energy: 310, hrAvg: 120)
        let previous = try #require(latest.previousOfSameType(in: [earlier, walk, latest]))
        #expect(previous.id == "lift-1")

        // Spec §F2's own phrasing, as numbers: "6 min longer, HR avg −3 bpm".
        let comparison = SessionComparison.between(latest, and: previous)
        #expect(comparison.durationMinutes == 6)
        #expect(comparison.hrAvgBpm == -3)
        #expect(comparison.activeEnergyKcal == 30)
        #expect(TrainFormat.signed(comparison.hrAvgBpm ?? 0) == "\u{2212}3")
        #expect(TrainFormat.signed(comparison.durationMinutes) == "+6")
    }

    @Test("a first session of its type has nothing to compare against")
    func theFirstSessionHasNoComparison() {
        let only = Fixture.session("lift", on: monday, hour: 18)
        #expect(only.previousOfSameType(in: [only]) == nil)
    }

    @Test("a delta against a measurement one side is missing is absent, not nought")
    func missingMeasurementsProduceNoDelta() {
        let earlier = Fixture.session("a", on: monday, hour: 18, energy: nil, hrAvg: 120)
        let later = Fixture.session("b", on: thursday, hour: 18, energy: 300, hrAvg: nil)
        let comparison = SessionComparison.between(later, and: earlier)
        #expect(comparison.activeEnergyKcal == nil)
        #expect(comparison.hrAvgBpm == nil)
        #expect(comparison.hrMaxBpm == 0)
    }

    @Test("a workout summary from the contract becomes a session this feature can read")
    func summariesConvert() throws {
        let summary = WorkoutSummary(
            healthKitId: "uuid", type: "traditionalStrengthTraining",
            startedAt: Timestamp.literal("2026-11-02T18:00:00-05:00"),
            endedAt: Timestamp.literal("2026-11-02T18:48:00-05:00"),
            durationMinutes: 48, activeEnergyKcal: 310, hrAvgBpm: 120, hrMaxBpm: 158,
            timeInZonesMinutes: TimeInZonesMinutes(z1: 14, z2: 22, z3: 10, z4: 2),
            source: "Apple Workout")
        let session = try #require(CompletedSession(summary))
        #expect(session.id == "uuid")
        #expect(session.modality == .strength)
        #expect(session.durationMinutes == 48)
        #expect(ZoneAnalysis(session.timeInZones).dominantZone == 2)
    }

    @Test("activity types map to the modality that matching turns on")
    func modalitiesCoverWhatTheProgramPrescribes() {
        #expect(TrainingModality(activityType: "traditionalStrengthTraining") == .strength)
        #expect(TrainingModality(activityType: "functionalStrengthTraining") == .strength)
        #expect(TrainingModality(activityType: "walking") == .cardio)
        #expect(TrainingModality(activityType: "cycling") == .cardio)
        #expect(TrainingModality(activityType: "yoga") == .other)
        #expect(SessionKind.rest.requiredModality == nil)
        #expect(SessionKind.zone2.requiredModality == .cardio)
        #expect(SessionKind.lowerB.requiredModality == .strength)
    }

    @Test("durations read as minutes until they read as hours")
    func durationsReadNaturally() {
        #expect(TrainFormat.duration(minutes: 48).value == "48")
        #expect(TrainFormat.duration(minutes: 48).unit == "min")
        #expect(TrainFormat.duration(minutes: 72).value == "1h12")
        #expect(TrainFormat.duration(minutes: 72).unit == nil)
        #expect(TrainFormat.weight(22.5) == "22.5")
        #expect(TrainFormat.weight(20) == "20")
    }
}
