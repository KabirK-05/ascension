import Foundation

/// A meal, or a glass of water, on its way into Apple Health.
///
/// `id` is the idempotency key and the caller owns it. ASC-12 passes the mutation's ULID,
/// so applying the same queued mutation twice — a retry, a duplicate silent push — writes
/// the same samples a second time under the same key, and HealthKit replaces rather than
/// adds. A random id per attempt would double-log the meal.
public struct NutritionEntry: Hashable, Sendable, Identifiable {
    public var id: String
    public var consumedAt: Date
    public var energyKcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var waterMl: Double?
    /// Bumped when the same entry is edited, so HealthKit keeps the newer version.
    public var revision: Int

    public init(id: String, consumedAt: Date, energyKcal: Double? = nil,
                proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil,
                waterMl: Double? = nil, revision: Int = 1) {
        self.id = id
        self.consumedAt = consumedAt
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.waterMl = waterMl
        self.revision = revision
    }

    public var values: [(HealthWriteMetric, Double)] {
        let pairs: [(HealthWriteMetric, Double?)] = [
            (.dietaryEnergy, energyKcal), (.dietaryProtein, proteinG),
            (.dietaryCarbohydrates, carbsG), (.dietaryFat, fatG), (.dietaryWater, waterMl)
        ]
        return pairs.compactMap { metric, value in value.map { (metric, $0) } }
    }
}

/// A manual weight or waist measurement (spec §6: the only body data the app writes).
public struct BodyMeasurementEntry: Hashable, Sendable, Identifiable {
    public var id: String
    public var measuredAt: Date
    public var weightKg: Double?
    public var waistCm: Double?
    public var revision: Int

    public init(id: String, measuredAt: Date, weightKg: Double? = nil, waistCm: Double? = nil,
                revision: Int = 1) {
        self.id = id
        self.measuredAt = measuredAt
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.revision = revision
    }

    public var values: [(HealthWriteMetric, Double)] {
        let pairs: [(HealthWriteMetric, Double?)] = [
            (.bodyMass, weightKg), (.waistCircumference, waistCm)
        ]
        return pairs.compactMap { metric, value in value.map { (metric, $0) } }
    }
}

/// Why a field in a write request produced no sample.
public enum WriteSkip: Hashable, Sendable {
    /// The user has refused this scope, or has not been asked yet.
    case notAuthorized(WriteAuthorization)
    /// Not a finite number, or negative. Zero is allowed: a zero-calorie drink is a fact.
    case invalidValue(Double)
}

/// What a write actually did. Returned rather than thrown so a partially authorized
/// write reports exactly which fields landed — the Eat screen needs to say so.
public struct HealthWriteReceipt: Hashable, Sendable {
    public var entryId: String
    public var saved: [WriteSample]
    public var skipped: [HealthWriteMetric: WriteSkip]

    public init(entryId: String, saved: [WriteSample] = [],
                skipped: [HealthWriteMetric: WriteSkip] = [:]) {
        self.entryId = entryId
        self.saved = saved
        self.skipped = skipped
    }

    public var didSaveEverything: Bool { skipped.isEmpty && !saved.isEmpty }
    public var savedMetrics: Set<HealthWriteMetric> { Set(saved.map(\.metric)) }
}

/// Builds the samples a write request turns into. Pure, so the exact bytes a retry would
/// produce can be asserted on without a store.
public enum HealthSampleFactory {
    /// Prefix for every sync identifier this app writes, so the keyspace is unmistakably
    /// ours and a future schema change can be versioned here.
    public static let syncIdentifierPrefix = "com.kabirkumar.ascension.v1"

    /// Deterministic: the same entry id, metric and revision always produce the same key.
    public static func syncIdentifier(entryId: String, metric: HealthWriteMetric) -> String {
        "\(syncIdentifierPrefix).\(metric.rawValue).\(entryId)"
    }

    public static func samples(for entry: NutritionEntry) -> (saved: [WriteSample],
                                                              skipped: [HealthWriteMetric: WriteSkip]) {
        build(entryId: entry.id, revision: entry.revision, instant: entry.consumedAt,
              values: entry.values)
    }

    public static func samples(for entry: BodyMeasurementEntry) -> (saved: [WriteSample],
                                                                    skipped: [HealthWriteMetric: WriteSkip]) {
        build(entryId: entry.id, revision: entry.revision, instant: entry.measuredAt,
              values: entry.values)
    }

    private static func build(entryId: String, revision: Int, instant: Date,
                              values: [(HealthWriteMetric, Double)])
        -> (saved: [WriteSample], skipped: [HealthWriteMetric: WriteSkip]) {
        var saved: [WriteSample] = []
        var skipped: [HealthWriteMetric: WriteSkip] = [:]
        for (metric, value) in values {
            guard value.isFinite, value >= 0 else {
                skipped[metric] = .invalidValue(value)
                continue
            }
            saved.append(WriteSample(
                metric: metric, value: value, start: instant, end: instant,
                syncIdentifier: syncIdentifier(entryId: entryId, metric: metric),
                syncVersion: max(1, revision)))
        }
        return (saved.sorted { $0.metric.rawValue < $1.metric.rawValue }, skipped)
    }
}
