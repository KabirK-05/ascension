import AscensionCore
import Foundation
import Testing

@testable import FeatureTrain

@Suite("time in zone and Zone 2 verification")
struct ZoneAnalysisTests {
    @Test("shares are of counted time, and they sum to one")
    func sharesAreOfCountedTime() {
        let analysis = ZoneAnalysis(TimeInZonesMinutes(z1: 5, z2: 10, z3: 5))
        #expect(analysis.total == 20)
        #expect(abs(analysis.share(ofZone: 2) - 0.5) < 0.0001)
        #expect(abs((1...5).map { analysis.share(ofZone: $0) }.reduce(0, +) - 1) < 0.0001)
        #expect(analysis.share(ofZone: 0) == 0)
        #expect(analysis.share(ofZone: 6) == 0)
    }

    @Test("a steady Zone 2 walk did not drift")
    func steadyZone2DidNotDrift() {
        let analysis = ZoneAnalysis(TimeInZonesMinutes(z1: 2, z2: 11.5, z3: 1.5))
        #expect(analysis.dominantZone == 2)
        #expect(analysis.driftedAboveZone2 == false)
    }

    @Test("a walk that spent more time above Zone 2 than in it drifted")
    func aWalkThatRanHotDrifted() {
        let analysis = ZoneAnalysis(TimeInZonesMinutes(z1: 1, z2: 4.5, z3: 8.5, z4: 1))
        #expect(analysis.dominantZone == 3)
        #expect(analysis.driftedAboveZone2)
    }

    @Test("a session with no heart-rate series has no dominant zone and no drift")
    func noSeriesMeansNoVerdict() {
        let analysis = ZoneAnalysis(TimeInZonesMinutes())
        #expect(analysis.isEmpty)
        #expect(analysis.dominantZone == nil)
        #expect(analysis.driftedAboveZone2 == false)
    }

    @Test("drift is read off the conditioning work, not off the lifting")
    func driftIsACardioVerdict() {
        let hot = TimeInZonesMinutes(z1: 1, z2: 4.5, z3: 8.5, z4: 1)
        let day = TrainingDay(date: Fixture.date("2026-11-02"), planned: .upperA, outcome: .completed)
        let walk = Fixture.session("walk", type: "walking", on: day.date, hour: 19,
                                   minutes: 15, zones: hot)
        let lift = Fixture.session("lift", on: day.date, hour: 18, zones: hot)

        // The lifting session's own zones are never the verdict, however hot they ran.
        let liftingOnly = SessionDebrief(day: day, session: lift, zones: ZoneAnalysis(hot))
        #expect(liftingOnly.conditioningDrifted == false)
        #expect(liftingOnly.conditioningZones == nil)

        // The finisher walk is what Zone 2 verification is about.
        let withFinisher = SessionDebrief(day: day, session: lift, zones: ZoneAnalysis(hot),
                                          conditioning: walk)
        #expect(withFinisher.conditioningDrifted)
        #expect(withFinisher.conditioningZones?.dominantZone == 3)
    }
}
