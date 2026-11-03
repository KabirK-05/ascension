import Foundation
import Testing

@testable import HealthBridge

@Suite("sleep nights")
struct SleepNightTests {
    @Test("a night is attributed to the morning the user woke up on")
    func nightBelongsToTheWakeDay() {
        let records = [
            Fixture.sleep("bed", stage: .inBed, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 7)),
            Fixture.sleep("core", stage: .asleepCore, start: Fixture.instant(hour: 23, minute: 20, day: 2),
                          end: Fixture.instant(hour: 7))
        ]
        let nights = SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone)

        #expect(nights.count == 1)
        #expect(nights.first?.date == Fixture.date("2026-11-03"))
        #expect(nights.first?.asleepMinutes == 460)
        #expect(nights.first?.inBedMinutes == 480)
    }

    @Test("overlapping samples from two sources are a union, not a sum")
    func overlapsAreUnioned() {
        let records = [
            Fixture.sleep("watch", stage: .asleepCore, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 3), source: "Apple Watch"),
            Fixture.sleep("phone", stage: .asleepUnspecified, start: Fixture.instant(hour: 1),
                          end: Fixture.instant(hour: 7), source: "iPhone")
        ]
        let nights = SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone)
        // 23:00 → 07:00 is eight hours. Summing the samples would claim ten.
        #expect(nights.first?.asleepMinutes == 480)
    }

    @Test("awake stretches come out of the in-bed total but never out of nowhere")
    func awakeIsSubtractedFromInBed() {
        let records = [
            Fixture.sleep("bed", stage: .inBed, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 7)),
            Fixture.sleep("core", stage: .asleepCore, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 3)),
            Fixture.sleep("awake", stage: .awake, start: Fixture.instant(hour: 3),
                          end: Fixture.instant(hour: 3, minute: 30)),
            Fixture.sleep("rem", stage: .asleepREM, start: Fixture.instant(hour: 3, minute: 30),
                          end: Fixture.instant(hour: 7))
        ]
        let nights = SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone)
        #expect(nights.first?.asleepMinutes == 450)
        #expect(nights.first?.inBedMinutes == 450)
    }

    @Test("an afternoon nap is not last night's sleep")
    func napsAreExcluded() {
        let records = [
            Fixture.sleep("night", stage: .asleepCore, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 7)),
            Fixture.sleep("nap", stage: .asleepCore, start: Fixture.instant(hour: 15),
                          end: Fixture.instant(hour: 15, minute: 40))
        ]
        let nights = SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone)
        #expect(nights.count == 1)
        #expect(nights.first?.asleepMinutes == 480)
    }

    @Test("a watch-only night reports no in-bed figure rather than guessing one")
    func inBedStaysNilWhenUnmeasured() {
        let records = [
            Fixture.sleep("core", stage: .asleepCore, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 6, minute: 30))
        ]
        let nights = SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone)
        #expect(nights.first?.inBedMinutes == nil)
        #expect(nights.first?.rollup.inBedMinutes == nil)
    }

    @Test("in-bed with no sleep stage produces no night at all")
    func inBedAloneIsNotSleep() {
        let records = [
            Fixture.sleep("bed", stage: .inBed, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 7))
        ]
        #expect(SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone).isEmpty)
    }

    @Test("rebuilding the same night produces the same row")
    func rebuildIsIdempotent() {
        let records = [
            Fixture.sleep("core", stage: .asleepCore, start: Fixture.instant(hour: 23, day: 2),
                          end: Fixture.instant(hour: 7))
        ]
        let first = SleepNightBuilder.nights(from: records, timeZone: Fixture.timeZone)
        let second = SleepNightBuilder.nights(from: records + records, timeZone: Fixture.timeZone)
        #expect(first == second)
        #expect(SleepNightBuilder.merging(existing: first, incoming: second) == first)
    }
}

@Suite("weight points")
struct WeightPointTests {
    @Test("the last reading of the day wins")
    func lastReadingWins() {
        let records = [
            Fixture.quantity("morning", metric: .bodyMass, value: 73.6,
                             start: Fixture.instant(hour: 7)),
            Fixture.quantity("correction", metric: .bodyMass, value: 73.9,
                             start: Fixture.instant(hour: 7, minute: 2))
        ]
        let points = WeightPointBuilder.points(from: records, timeZone: Fixture.timeZone)
        #expect(points.count == 1)
        #expect(points.first?.weightKg == 73.9)
        #expect(points.first?.sourceSampleId == Fixture.id("correction").uuidString)
    }

    @Test("one point per day, in date order")
    func onePointPerDay() {
        let records = [
            Fixture.quantity("d3", metric: .bodyMass, value: 73.6, start: Fixture.instant(hour: 7)),
            Fixture.quantity("d4", metric: .bodyMass, value: 73.4,
                             start: Fixture.instant(hour: 7, day: 4))
        ]
        let points = WeightPointBuilder.points(from: records, timeZone: Fixture.timeZone)
        #expect(points.map(\.date.rawValue) == ["2026-11-03", "2026-11-04"])
    }

    @Test("rebuilding from the same samples changes nothing")
    func rebuildIsIdempotent() {
        let records = [
            Fixture.quantity("d3", metric: .bodyMass, value: 73.6, start: Fixture.instant(hour: 7))
        ]
        let first = WeightPointBuilder.points(from: records, timeZone: Fixture.timeZone)
        let second = WeightPointBuilder.points(from: records + records, timeZone: Fixture.timeZone)
        #expect(first == second)
        #expect(WeightPointBuilder.merging(existing: first, incoming: second) == first)
    }

    @Test("a day boundary is the user's midnight, not UTC's")
    func dayBoundaryFollowsTheUsersTimezone() {
        // 23:30 in Toronto is already the next day in UTC. The contract keys on local days.
        let late = Fixture.quantity("late", metric: .bodyMass, value: 73.6,
                                    start: Fixture.instant(hour: 23, minute: 30))
        let points = WeightPointBuilder.points(from: [late], timeZone: Fixture.timeZone)
        #expect(points.first?.date == Fixture.date("2026-11-03"))
    }
}
