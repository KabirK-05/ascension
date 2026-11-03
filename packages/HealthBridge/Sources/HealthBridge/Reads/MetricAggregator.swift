import Foundation

/// The reference semantics for collapsing samples into one number.
///
/// Every aggregation deduplicates on HealthKit UUID first. An observer callback fires
/// more than once for the same data, and a mirror pass may be handed overlapping pages,
/// so the same sample arriving twice must not count twice.
///
/// `HKHealthStoreAdapter` answers the same questions with `HKStatisticsQuery`, which is
/// the right tool on device (it merges overlapping samples from the iPhone and the Watch
/// for cumulative types). These functions define what that query is expected to mean,
/// and are what the fake store computes, so the semantics are what the tests pin down.
public enum MetricAggregator {
    /// Sum of distinct samples. `nil` when there are none — the contract's `null` means
    /// not measured, and a day with no step samples has not measured zero steps.
    public static func total(_ records: [QuantityRecord]) -> Double? {
        let distinct = deduplicated(records)
        guard !distinct.isEmpty else { return nil }
        return distinct.reduce(0) { $0 + $1.value }
    }

    /// Mean of distinct samples, unweighted — HealthKit's `discreteAverage`.
    public static func average(_ records: [QuantityRecord]) -> Double? {
        let distinct = deduplicated(records)
        guard !distinct.isEmpty else { return nil }
        return distinct.reduce(0) { $0 + $1.value } / Double(distinct.count)
    }

    /// The newest sample. Ties on `end` break on `start`, then on UUID, so the answer is
    /// deterministic rather than dependent on the order HealthKit happened to return.
    public static func mostRecent(_ records: [QuantityRecord]) -> Double? {
        latest(records)?.value
    }

    public static func latest(_ records: [QuantityRecord]) -> QuantityRecord? {
        deduplicated(records).max { lhs, rhs in
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public static func maximum(_ records: [QuantityRecord]) -> Double? {
        deduplicated(records).map(\.value).max()
    }

    /// Stand hours: HealthKit records one sample per hour, value `0` for "stood".
    /// Counted, never summed.
    public static func standHours(_ records: [CategoryRecord]) -> Int? {
        let distinct = deduplicatedCategories(records)
        guard !distinct.isEmpty else { return nil }
        return distinct.count { $0.value == 0 }
    }

    /// Distinct samples in a stable order: by start, then end, then UUID.
    public static func deduplicated(_ records: [QuantityRecord]) -> [QuantityRecord] {
        var seen = Set<UUID>()
        let distinct = records.filter { seen.insert($0.id).inserted }
        return distinct.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public static func deduplicatedCategories(_ records: [CategoryRecord]) -> [CategoryRecord] {
        var seen = Set<UUID>()
        let distinct = records.filter { seen.insert($0.id).inserted }
        return distinct.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public static func deduplicatedWorkouts(_ records: [WorkoutRecord]) -> [WorkoutRecord] {
        var seen = Set<UUID>()
        let distinct = records.filter { seen.insert($0.id).inserted }
        return distinct.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Applies the aggregation a metric declares. Used by the fake store so the reader
    /// and the device agree on what each metric means.
    public static func apply(_ aggregation: MetricAggregation,
                             to records: [QuantityRecord]) -> Double? {
        switch aggregation {
        case .cumulativeTotal: return total(records)
        case .dailyAverage: return average(records)
        case .mostRecent, .series: return mostRecent(records)
        case .categoryCount, .categoryIntervals, .workoutRecords: return nil
        }
    }
}
