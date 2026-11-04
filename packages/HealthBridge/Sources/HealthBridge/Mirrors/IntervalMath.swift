import Foundation

/// Interval arithmetic the mirrors need.
///
/// Sleep arrives as overlapping samples — the Watch and the iPhone both describe the same
/// stretch of night — so durations are measured over the *union* of intervals. Summing
/// them would invent hours of sleep that never happened.
public enum IntervalMath {
    /// Overlapping and touching intervals merged, in ascending order.
    public static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start,
                                                        end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Total seconds covered by the union of `intervals`.
    public static func coveredSeconds(_ intervals: [DateInterval]) -> TimeInterval {
        union(intervals).reduce(0) { $0 + $1.duration }
    }

    /// Union minutes, rounded to the nearest minute — the contract's unit.
    public static func coveredMinutes(_ intervals: [DateInterval]) -> Int {
        Int((coveredSeconds(intervals) / 60).rounded())
    }

    /// `intervals` with every part of `cutouts` removed. Used to take the awake stretches
    /// out of an in-bed interval.
    public static func subtracting(
        _ cutouts: [DateInterval],
        from intervals: [DateInterval]
    ) -> [DateInterval] {
        let holes = union(cutouts)
        var remaining = union(intervals)
        for hole in holes {
            remaining = remaining.flatMap { piece -> [DateInterval] in
                guard piece.intersects(hole) else { return [piece] }
                var parts: [DateInterval] = []
                if piece.start < hole.start {
                    parts.append(DateInterval(start: piece.start, end: hole.start))
                }
                if hole.end < piece.end {
                    parts.append(DateInterval(start: hole.end, end: piece.end))
                }
                return parts
            }
        }
        return remaining
    }

    /// `interval` clipped to `bounds`, or `nil` when they do not overlap.
    public static func clipped(_ interval: DateInterval, to bounds: DateInterval) -> DateInterval? {
        let start = max(interval.start, bounds.start)
        let end = min(interval.end, bounds.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }
}
