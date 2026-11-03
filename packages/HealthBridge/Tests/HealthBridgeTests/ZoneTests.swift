import AscensionCore
import Foundation
import Testing

@testable import HealthBridge

@Suite("time-in-zone and Zone 2 verification")
struct ZoneTests {
    private let zones = HeartRateZones.forAge(25)

    @Test("Tanaka's estimate and the percent-of-max bounds")
    func boundsFollowPercentOfMax() {
        #expect(HeartRateZones.estimatedMaxHeartRate(age: 25) == 190.5)
        #expect(zones.lowerBounds.count == 5)
        #expect(abs((zones.lowerBounds.first ?? 0) - 95.25) < 0.001)
        #expect(abs((zones.lowerBounds.last ?? 0) - 171.45) < 0.001)
    }

    @Test("a reading lands in one zone, and resting beats land in none")
    func zoneLookup() {
        #expect(zones.zone(forBpm: 60) == nil)
        #expect(zones.zone(forBpm: 100) == 1)
        #expect(zones.zone(forBpm: 120) == 2)
        #expect(zones.zone(forBpm: 140) == 3)
        #expect(zones.zone(forBpm: 160) == 4)
        #expect(zones.zone(forBpm: 200) == 5)
    }

    @Test("a steady Zone 2 ride counts its minutes in Zone 2 and nowhere else")
    func steadyZone2() {
        let start = Fixture.instant(hour: 18)
        let series = Fixture.heartRateSeries("z2", from: start,
                                             bpms: [Double](repeating: 125, count: 40),
                                             everySeconds: 30)
        let workout = DateInterval(start: start, duration: 20 * 60)
        let minutes = TimeInZoneCalculator.minutes(series: series, workout: workout, zones: zones)

        #expect(minutes.z2 == 20)
        #expect(minutes.z1 == 0)
        #expect(minutes.z3 == 0)
        #expect(minutes.driftedAboveZone2 == false)
        #expect(minutes.dominantZone == 2)
    }

    @Test("a session that drifted into Zone 3 is flagged (spec §F2)")
    func driftIsFlagged() {
        let start = Fixture.instant(hour: 18)
        let bpms = [Double](repeating: 125, count: 10) + [Double](repeating: 145, count: 30)
        let series = Fixture.heartRateSeries("drift", from: start, bpms: bpms, everySeconds: 30)
        let workout = DateInterval(start: start, duration: 20 * 60)
        let minutes = TimeInZoneCalculator.minutes(series: series, workout: workout, zones: zones)

        #expect(minutes.z2 == 5)
        #expect(minutes.z3 == 15)
        #expect(minutes.driftedAboveZone2)
        #expect(minutes.dominantZone == 3)
    }

    @Test("a dropout is left uncounted rather than credited to the last beat seen")
    func gapsAreNotInvented() {
        let start = Fixture.instant(hour: 18)
        let early = Fixture.quantity("hr-1", metric: .heartRate, value: 125, start: start)
        let late = Fixture.quantity("hr-2", metric: .heartRate, value: 125,
                                    start: start.addingTimeInterval(15 * 60))
        let workout = DateInterval(start: start, duration: 20 * 60)
        let minutes = TimeInZoneCalculator.minutes(series: [early, late], workout: workout,
                                                   zones: zones)

        // One minute held per sample, capped by `defaultMaxHold`; the 14-minute hole is
        // not sleep-walked into Zone 2.
        #expect(minutes.z2 == 2)
        #expect(minutes.total < 20)
    }

    @Test("samples outside the workout are clipped away")
    func samplesOutsideTheWorkoutAreClipped() {
        let start = Fixture.instant(hour: 18)
        let workout = DateInterval(start: start, duration: 10 * 60)
        let before = Fixture.quantity("hr-before", metric: .heartRate, value: 125,
                                      start: start.addingTimeInterval(-600))
        let inside = Fixture.quantity("hr-inside", metric: .heartRate, value: 125,
                                      start: start.addingTimeInterval(60))
        let minutes = TimeInZoneCalculator.minutes(series: [before, inside], workout: workout,
                                                   zones: zones)
        #expect(minutes.z2 == 1)
    }

    @Test("duplicate heart-rate samples do not double-count a minute")
    func duplicateBeatsDoNotDoubleCount() {
        let start = Fixture.instant(hour: 18)
        let series = Fixture.heartRateSeries("dupe", from: start,
                                             bpms: [Double](repeating: 125, count: 10),
                                             everySeconds: 30)
        let workout = DateInterval(start: start, duration: 5 * 60)
        let single = TimeInZoneCalculator.minutes(series: series, workout: workout, zones: zones)
        let doubled = TimeInZoneCalculator.minutes(series: series + series, workout: workout,
                                                   zones: zones)
        #expect(single == doubled)
    }

    @Test("a workout mirror carries HR average, max and the zone breakdown")
    func mirrorCarriesHeartRateFigures() {
        let start = Fixture.instant(hour: 19, minute: 4)
        let record = Fixture.workout("upper-a", start: start, minutes: 51)
        let series = Fixture.heartRateSeries("upper-hr", from: start,
                                             bpms: [110, 120, 130, 150], everySeconds: 60)
        let mirror = WorkoutMirrorBuilder.mirror(for: record, series: series, zones: zones)

        #expect(mirror.hrAvgBpm == 128)
        #expect(mirror.hrMaxBpm == 150)
        #expect(mirror.durationMinutes == 51)
        #expect(mirror.source == "Apple Workout")
        #expect(mirror.timeInZones.total > 0)
    }

    @Test("no heart-rate series means no heart-rate figures, not zeroes")
    func missingSeriesStaysMissing() {
        let record = Fixture.workout("upper-a", start: Fixture.instant(hour: 19), minutes: 51)
        let mirror = WorkoutMirrorBuilder.mirror(for: record, series: [], zones: zones)
        #expect(mirror.hrAvgBpm == nil)
        #expect(mirror.hrMaxBpm == nil)
        #expect(mirror.timeInZones == TimeInZonesMinutes())
    }

    @Test("a mirror becomes the contract's workout summary")
    func mirrorMapsToTheContract() {
        let start = Fixture.instant(hour: 19, minute: 4)
        let record = Fixture.workout("upper-a", start: start, minutes: 51)
        let mirror = WorkoutMirrorBuilder.mirror(for: record, series: [], zones: zones)
        let summary = mirror.summary(timeZone: Fixture.timeZone)

        #expect(summary.healthKitId == mirror.id)
        #expect(summary.type == "traditionalStrengthTraining")
        #expect(summary.durationMinutes == 51)
        #expect(summary.startedAt.rawValue == "2026-11-03T19:04:00-05:00")
        #expect(summary.source == "Apple Workout")
    }
}
