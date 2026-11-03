import AscensionCore
import Foundation

/// Five heart-rate zones, as bpm lower bounds.
///
/// Spec §F2 wants Zone 2 verified on cardio — "flag if most of the session drifted into
/// Zone 3" — which needs zone boundaries the app owns. Nothing in the contract defines
/// them, so they are defined here: configurable, with a percent-of-max default.
public struct HeartRateZones: Hashable, Sendable {
    /// Ascending bpm lower bounds for zones 1 through 5.
    public let lowerBounds: [Double]

    public init?(lowerBounds: [Double]) {
        guard lowerBounds.count == 5,
              lowerBounds.allSatisfy({ $0 > 0 }),
              zip(lowerBounds, lowerBounds.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        self.lowerBounds = lowerBounds
    }

    private init(unchecked lowerBounds: [Double]) {
        self.lowerBounds = lowerBounds
    }

    /// Zones at 50 / 60 / 70 / 80 / 90 % of maximum heart rate — the percent-of-max
    /// convention Apple Fitness and most cardio guidance use.
    ///
    /// Non-failable: the maximum is clamped to a plausible 120–220 bpm, which keeps the
    /// bounds ascending whatever is passed in.
    public static func percentOfMax(_ maxHeartRate: Double) -> HeartRateZones {
        let bounded = min(220, max(120, maxHeartRate.isFinite ? maxHeartRate : 190))
        return HeartRateZones(unchecked: [0.50, 0.60, 0.70, 0.80, 0.90].map { $0 * bounded })
    }

    /// The zones for an age, via the Tanaka estimate.
    public static func forAge(_ age: Int) -> HeartRateZones {
        percentOfMax(estimatedMaxHeartRate(age: age))
    }

    /// Tanaka's estimate, `208 − 0.7 × age`, which fits adults better than `220 − age`.
    /// An estimate: a measured maximum from a hard effort should be preferred when known.
    public static func estimatedMaxHeartRate(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }

    /// The zone a reading falls in, 1 through 5. `nil` below zone 1 — resting and
    /// recovery beats are not training time and are not credited to a zone.
    public func zone(forBpm bpm: Double) -> Int? {
        guard let index = lowerBounds.lastIndex(where: { bpm >= $0 }) else { return nil }
        return index + 1
    }
}

/// Minutes in each zone, computed from a workout's heart-rate series.
public enum TimeInZoneCalculator {
    /// How long one reading is taken to hold before the next one. A gap longer than this
    /// is left uncounted rather than attributed to the last beat seen, so zone totals can
    /// be less than the workout duration — which is the truth when the strap dropped out.
    public static let defaultMaxHold: TimeInterval = 60

    /// Step-hold integration: each sample holds its value until the next sample starts,
    /// clipped to `workout` and capped at `maxHold`.
    public static func minutes(series: [QuantityRecord],
                               workout: DateInterval,
                               zones: HeartRateZones,
                               maxHold: TimeInterval = defaultMaxHold) -> TimeInZonesMinutes {
        let samples = MetricAggregator.deduplicated(series).filter { $0.metric == .heartRate }
        var seconds = [Double](repeating: 0, count: 5)
        for (index, sample) in samples.enumerated() {
            guard let zone = zones.zone(forBpm: sample.value) else { continue }
            let nextStart = index + 1 < samples.count ? samples[index + 1].start : workout.end
            let holdEnd = min(max(sample.start, nextStart), sample.start.addingTimeInterval(maxHold))
            let span = DateInterval(start: sample.start, end: max(sample.start, holdEnd))
            guard let clipped = IntervalMath.clipped(span, to: workout) else { continue }
            seconds[zone - 1] += clipped.duration
        }
        return TimeInZonesMinutes(
            z1: minutes(seconds[0]), z2: minutes(seconds[1]), z3: minutes(seconds[2]),
            z4: minutes(seconds[3]), z5: minutes(seconds[4]))
    }

    private static func minutes(_ seconds: Double) -> Double {
        ((seconds / 60) * 10).rounded() / 10
    }
}

extension TimeInZonesMinutes {
    /// Spec §F2: a Zone 2 session that spent more of its time above Zone 2 than in it
    /// drifted, and the debrief says so.
    public var driftedAboveZone2: Bool {
        let above = z3 + z4 + z5
        return total > 0 && above > z2
    }

    /// The zone that held the most time, 1 through 5. `nil` when nothing was counted.
    public var dominantZone: Int? {
        let ordered = [z1, z2, z3, z4, z5]
        guard let peak = ordered.max(), peak > 0 else { return nil }
        return (ordered.firstIndex(of: peak) ?? 0) + 1
    }
}
