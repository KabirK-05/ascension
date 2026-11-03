import Foundation
import HealthBridge

/// A `HealthStore` with no HealthKit behind it.
///
/// The seam exists for exactly this: CI has no HealthKit, and the shell's whole job is to
/// turn a store's answers into a rollup. With this in place the live path — authorization,
/// a day's snapshot, the matcher, the ledger, readiness — is exercised end to end on a
/// machine that has never seen an Apple Watch.
///
/// `@unchecked Sendable` over a lock rather than an actor: `HealthStore` is a synchronous
/// protocol in places (`writeStatus`, `startObserving`), so an actor cannot conform to it.
/// Every mutable field is behind the lock.
final class FakeHealthStore: HealthStore, @unchecked Sendable {
    private let lock = NSLock()
    private var quantities: [QuantityRecord] = []
    private var categories: [CategoryRecord] = []
    private var workoutRecords: [WorkoutRecord] = []
    private var saved: [WriteSample] = []
    private var writeStatuses: [HealthWriteMetric: WriteAuthorization] = [:]

    var isHealthDataAvailable: Bool = true
    private(set) var authorizationRequests = 0
    private(set) var backgroundDeliveryMetrics: Set<HealthMetric> = []
    private(set) var observedMetrics: Set<HealthMetric> = []

    init() {}

    // MARK: - Arranging

    func add(_ records: [QuantityRecord]) {
        lock.withLock { quantities.append(contentsOf: records) }
    }

    func add(_ records: [CategoryRecord]) {
        lock.withLock { categories.append(contentsOf: records) }
    }

    func add(_ records: [WorkoutRecord]) {
        lock.withLock { workoutRecords.append(contentsOf: records) }
    }

    func allow(_ metric: HealthWriteMetric, _ status: WriteAuthorization = .granted) {
        lock.withLock { writeStatuses[metric] = status }
    }

    var savedSamples: [WriteSample] { lock.withLock { saved } }

    // MARK: - HealthStore

    func requestAuthorization(read: Set<HealthMetric>, write: Set<HealthWriteMetric>) async throws {
        lock.withLock { authorizationRequests += 1 }
    }

    func writeStatus(for metric: HealthWriteMetric) -> WriteAuthorization {
        lock.withLock { writeStatuses[metric] ?? .notDetermined }
    }

    func authorizationRequestStatus(read: Set<HealthMetric>,
                                    write: Set<HealthWriteMetric>) async throws
        -> AuthorizationRequest {
        .unnecessary
    }

    /// Computed with `MetricAggregator`, which is the reference definition of each
    /// aggregation — the same route `HealthBridge`'s own fake takes, so a number here means
    /// what it would mean on a device.
    func statistic(_ metric: HealthMetric, in interval: DateInterval) async throws -> Double? {
        let records = try await quantitySamples(metric, in: interval)
        return MetricAggregator.apply(metric.aggregation, to: records)
    }

    func quantitySamples(_ metric: HealthMetric,
                         in interval: DateInterval) async throws -> [QuantityRecord] {
        lock.withLock {
            quantities.filter { $0.metric == metric && interval.intersects($0.interval) }
        }
    }

    func categorySamples(_ metric: HealthMetric,
                         in interval: DateInterval) async throws -> [CategoryRecord] {
        lock.withLock {
            categories.filter { $0.metric == metric && interval.intersects($0.interval) }
        }
    }

    func workouts(in interval: DateInterval) async throws -> [WorkoutRecord] {
        lock.withLock { workoutRecords.filter { interval.intersects($0.interval) } }
    }

    func heartRateSeries(forWorkout id: UUID,
                         in interval: DateInterval) async throws -> [QuantityRecord] {
        try await quantitySamples(.heartRate, in: interval)
    }

    func anchoredWorkouts(since anchor: HealthAnchorToken?) async throws -> AnchoredWorkouts {
        AnchoredWorkouts(workouts: lock.withLock { workoutRecords },
                         deletedIds: [],
                         anchor: HealthAnchorToken(rawValue: Data([1])))
    }

    func save(_ samples: [WriteSample]) async throws {
        lock.withLock { saved.append(contentsOf: samples) }
    }

    func startObserving(_ metrics: Set<HealthMetric>,
                        onChange: @escaping HealthChangeHandler) throws {
        lock.withLock { observedMetrics = metrics }
    }

    func enableBackgroundDelivery(for metrics: Set<HealthMetric>) async throws {
        lock.withLock { backgroundDeliveryMetrics = metrics }
    }

    func disableAllBackgroundDelivery() async throws {
        lock.withLock { backgroundDeliveryMetrics = [] }
    }
}
