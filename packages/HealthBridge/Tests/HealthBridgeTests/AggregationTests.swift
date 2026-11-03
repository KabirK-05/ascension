import Foundation
import Testing

@testable import HealthBridge

@Suite("aggregation and interval arithmetic")
struct AggregationTests {
    private let morning = Fixture.instant(hour: 7)

    @Test("the same sample twice counts once")
    func duplicatesAreDropped() {
        let sample = Fixture.quantity("steps", metric: .steps, value: 4_000, start: morning)
        #expect(MetricAggregator.total([sample, sample]) == 4_000)
        #expect(MetricAggregator.average([sample, sample]) == 4_000)
        #expect(MetricAggregator.deduplicated([sample, sample]).count == 1)
    }

    @Test("no samples means nil, because the contract's null is not a zero")
    func emptyIsNil() {
        #expect(MetricAggregator.total([]) == nil)
        #expect(MetricAggregator.average([]) == nil)
        #expect(MetricAggregator.mostRecent([]) == nil)
        #expect(MetricAggregator.standHours([]) == nil)
    }

    @Test("most recent breaks ties deterministically")
    func mostRecentIsDeterministic() {
        let first = Fixture.quantity("aaa", metric: .bodyMass, value: 73.6, start: morning)
        let second = Fixture.quantity("zzz", metric: .bodyMass, value: 74.0, start: morning)
        #expect(MetricAggregator.mostRecent([first, second])
            == MetricAggregator.mostRecent([second, first]))
    }

    @Test("stand hours are counted, and an idle hour does not count")
    func standHoursAreCounted() {
        let records = [
            Fixture.standHour("h8", at: Fixture.instant(hour: 8)),
            Fixture.standHour("h9", at: Fixture.instant(hour: 9), stood: false),
            Fixture.standHour("h10", at: Fixture.instant(hour: 10))
        ]
        #expect(MetricAggregator.standHours(records) == 2)
    }

    @Test("overlapping intervals merge")
    func unionMergesOverlaps() {
        let first = DateInterval(start: morning, duration: 3_600)
        let second = DateInterval(start: morning.addingTimeInterval(1_800), duration: 3_600)
        let union = IntervalMath.union([second, first])
        #expect(union.count == 1)
        #expect(union.first?.duration == 5_400)
    }

    @Test("disjoint intervals stay apart")
    func unionKeepsGaps() {
        let first = DateInterval(start: morning, duration: 600)
        let second = DateInterval(start: morning.addingTimeInterval(1_200), duration: 600)
        #expect(IntervalMath.union([first, second]).count == 2)
        #expect(IntervalMath.coveredMinutes([first, second]) == 20)
    }

    @Test("subtracting a hole splits the interval")
    func subtractionSplits() {
        let whole = DateInterval(start: morning, duration: 3_600)
        let hole = DateInterval(start: morning.addingTimeInterval(1_200), duration: 600)
        let remaining = IntervalMath.subtracting([hole], from: [whole])
        #expect(remaining.count == 2)
        #expect(IntervalMath.coveredSeconds(remaining) == 3_000)
    }

    @Test("clipping outside the bounds yields nothing")
    func clippingOutsideIsNil() {
        let bounds = DateInterval(start: morning, duration: 600)
        let outside = DateInterval(start: morning.addingTimeInterval(1_200), duration: 600)
        #expect(IntervalMath.clipped(outside, to: bounds) == nil)
    }
}
