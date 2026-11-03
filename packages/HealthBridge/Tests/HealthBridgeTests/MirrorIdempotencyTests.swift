import Foundation
import Testing

@testable import HealthBridge

/// The single most important property in this ticket: a mirror pass over the same source
/// data produces identical rows, however many times it runs.
@Suite("mirrors are idempotent on HealthKit UUIDs")
struct MirrorIdempotencyTests {
    private let start = Fixture.instant(hour: 19, minute: 4)

    private func records() -> [WorkoutRecord] {
        [
            Fixture.workout("upper-a", start: start, minutes: 51),
            Fixture.workout("walk", type: "walking", start: Fixture.instant(hour: 7), minutes: 22)
        ]
    }

    @Test("a second pass over the same workouts changes nothing")
    func secondPassIsANoOp() {
        let first = WorkoutMirrorBuilder.mirrors(from: records(), zones: Fixture.zones)
        let second = WorkoutMirrorBuilder.mirrors(from: records(), zones: Fixture.zones)
        #expect(first == second)

        let once = WorkoutMirrorBuilder.merging(existing: [], incoming: first)
        let twice = WorkoutMirrorBuilder.merging(existing: once, incoming: second)
        let thrice = WorkoutMirrorBuilder.merging(existing: twice, incoming: first)
        #expect(once == twice)
        #expect(twice == thrice)
        #expect(once.count == 2)
    }

    @Test("the same workout handed over twice in one batch yields one row")
    func duplicatesWithinABatchCollapse() {
        let duplicated = records() + records()
        let mirrors = WorkoutMirrorBuilder.mirrors(from: duplicated, zones: Fixture.zones)
        #expect(mirrors.count == 2)
        #expect(Set(mirrors.map(\.id)).count == 2)
    }

    @Test("an edited workout replaces its row instead of adding one")
    func editedWorkoutUpserts() {
        let original = WorkoutMirrorBuilder.mirrors(from: records(), zones: Fixture.zones)
        let corrected = Fixture.workout("upper-a", start: start, minutes: 57, energy: 402)
        let incoming = WorkoutMirrorBuilder.mirrors(from: [corrected], zones: Fixture.zones)
        let merged = WorkoutMirrorBuilder.merging(existing: original, incoming: incoming)

        #expect(merged.count == 2)
        let row = merged.first { $0.id == Fixture.id("upper-a").uuidString }
        #expect(row?.durationMinutes == 57)
        #expect(row?.activeEnergyKcal == 402)
    }

    @Test("a deleted workout drops out of the mirror")
    func deletionRemovesTheRow() {
        let mirrors = WorkoutMirrorBuilder.mirrors(from: records(), zones: Fixture.zones)
        let merged = WorkoutMirrorBuilder.merging(
            existing: mirrors, incoming: [],
            deletedIds: [Fixture.id("walk").uuidString])
        #expect(merged.count == 1)
        #expect(merged.first?.id == Fixture.id("upper-a").uuidString)
    }

    @Test("merge order does not change the result")
    func mergeIsOrderIndependent() {
        let mirrors = WorkoutMirrorBuilder.mirrors(from: records(), zones: Fixture.zones)
        guard let first = mirrors.first, let second = mirrors.last else {
            Issue.record("fixture produced no mirrors")
            return
        }
        let forwards = WorkoutMirrorBuilder.merging(existing: [first], incoming: [second])
        let backwards = WorkoutMirrorBuilder.merging(existing: [second], incoming: [first])
        #expect(forwards == backwards)
    }

    @Test("a whole mirror set folds into itself unchanged")
    func mirrorSetMergeIsStable() {
        let set = MirrorSet(
            workouts: WorkoutMirrorBuilder.mirrors(from: records(), zones: Fixture.zones),
            nights: [SleepNight(date: Fixture.date("2026-11-03"),
                                start: Fixture.instant(hour: 23, day: 2),
                                end: Fixture.instant(hour: 7),
                                asleepMinutes: 462, inBedMinutes: 495)],
            weights: [WeightPoint(date: Fixture.date("2026-11-03"), weightKg: 73.6,
                                  measuredAt: Fixture.instant(hour: 7),
                                  sourceSampleId: Fixture.id("weigh-in").uuidString)])
        #expect(set.merging(set) == set)
        #expect(set.merging(set).merging(set) == set)
    }
}
