import Foundation

@testable import HealthBridge

/// A `HealthStore` that holds its samples in memory.
///
/// Exists because HealthKit cannot be created, authorized or populated in a test — not on
/// macOS, not in CI, not even in a simulator without a user tapping the sheet. Everything
/// this module decides is decided above the protocol, so everything can be tested here.
///
/// Anchored reads behave the way HealthKit's do: the anchor is a resume point, so a second
/// pass with the anchor the first returned comes back empty. That is the behaviour the
/// idempotency tests lean on.
final class FakeHealthStore: HealthStore, @unchecked Sendable {
    struct Config: Sendable {
        var available = true
        var requestStatus: AuthorizationRequest = .unnecessary
        var writeStatuses: [HealthWriteMetric: WriteAuthorization] = Dictionary(
            uniqueKeysWithValues: HealthWriteMetric.allCases.map { ($0, .granted) })
        var quantities: [HealthMetric: [QuantityRecord]] = [:]
        var categories: [HealthMetric: [CategoryRecord]] = [:]
        var workouts: [WorkoutRecord] = []
        var heartRate: [UUID: [QuantityRecord]] = [:]
        var failingMetrics: Set<HealthMetric> = []
        var saveError: HealthStoreError?
    }

    private let lock = NSLock()
    private var config: Config
    private var pendingDeletions: [UUID] = []
    private var savedSamples: [WriteSample] = []
    private var requestedRead: Set<HealthMetric> = []
    private var requestedWrite: Set<HealthWriteMetric> = []
    private var observing: Set<HealthMetric> = []
    private var backgroundDelivery: Set<HealthMetric> = []
    private var changeHandler: HealthChangeHandler?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Inspection

    var saved: [WriteSample] { lock.withLock { savedSamples } }
    var authorizationAsked: (read: Set<HealthMetric>, write: Set<HealthWriteMetric>) {
        lock.withLock { (requestedRead, requestedWrite) }
    }
    var observedMetrics: Set<HealthMetric> { lock.withLock { observing } }
    var backgroundDeliveryMetrics: Set<HealthMetric> { lock.withLock { backgroundDelivery } }

    func update(_ mutate: (inout Config) -> Void) {
        lock.withLock { mutate(&config) }
    }

    func queueDeletions(_ ids: [UUID]) {
        lock.withLock { pendingDeletions.append(contentsOf: ids) }
    }

    /// Fires the observer callback the way HealthKit would, and reports whether the
    /// completion handler came back — the thing iOS punishes an app for forgetting.
    func fireObserver(_ metric: HealthMetric) async -> Bool {
        let handler = lock.withLock { changeHandler }
        guard let handler else { return false }
        return await withCheckedContinuation { continuation in
            handler(metric) { continuation.resume(returning: true) }
        }
    }

    // MARK: - HealthStore

    var isHealthDataAvailable: Bool { lock.withLock { config.available } }

    func requestAuthorization(read: Set<HealthMetric>, write: Set<HealthWriteMetric>) async throws {
        try lock.withLock {
            guard config.available else { throw HealthStoreError.healthDataUnavailable }
            requestedRead = read
            requestedWrite = write
        }
    }

    func writeStatus(for metric: HealthWriteMetric) -> WriteAuthorization {
        lock.withLock { config.writeStatuses[metric] ?? .notDetermined }
    }

    func authorizationRequestStatus(
        read: Set<HealthMetric>,
        write: Set<HealthWriteMetric>
    ) async throws -> AuthorizationRequest {
        lock.withLock { config.requestStatus }
    }

    func statistic(_ metric: HealthMetric, in interval: DateInterval) async throws -> Double? {
        let records = try samples(metric, in: interval)
        return MetricAggregator.apply(metric.aggregation, to: records)
    }

    func quantitySamples(_ metric: HealthMetric,
                         in interval: DateInterval) async throws -> [QuantityRecord] {
        try samples(metric, in: interval)
    }

    func categorySamples(_ metric: HealthMetric,
                         in interval: DateInterval) async throws -> [CategoryRecord] {
        try lock.withLock {
            guard config.available else { throw HealthStoreError.healthDataUnavailable }
            guard !config.failingMetrics.contains(metric) else {
                throw HealthStoreError.queryFailed("fake failure: \(metric.rawValue)")
            }
            let samples = config.categories[metric] ?? []
            return samples.filter { $0.start < interval.end && $0.end > interval.start }
        }
    }

    func workouts(in interval: DateInterval) async throws -> [WorkoutRecord] {
        try lock.withLock {
            guard config.available else { throw HealthStoreError.healthDataUnavailable }
            guard !config.failingMetrics.contains(.workouts) else {
                throw HealthStoreError.queryFailed("fake failure: workouts")
            }
            return config.workouts.filter { $0.start < interval.end && $0.end > interval.start }
        }
    }

    func heartRateSeries(forWorkout id: UUID,
                         in interval: DateInterval) async throws -> [QuantityRecord] {
        lock.withLock { config.heartRate[id] ?? [] }
    }

    func anchoredWorkouts(since anchor: HealthAnchorToken?) async throws -> AnchoredWorkouts {
        try lock.withLock {
            guard config.available else { throw HealthStoreError.healthDataUnavailable }
            let resume = anchor
                .flatMap { String(bytes: $0.rawValue, encoding: .utf8) }
                .flatMap(Int.init) ?? 0
            let fresh = Array(config.workouts.dropFirst(resume))
            let deletions = pendingDeletions
            pendingDeletions = []
            let token = HealthAnchorToken(rawValue: Data("\(config.workouts.count)".utf8))
            return AnchoredWorkouts(workouts: fresh, deletedIds: deletions, anchor: token)
        }
    }

    func save(_ samples: [WriteSample]) async throws {
        try lock.withLock {
            if let error = config.saveError { throw error }
            // HealthKit replaces a sample carrying a sync identifier it already holds.
            for sample in samples {
                let existing = savedSamples.firstIndex { $0.syncIdentifier == sample.syncIdentifier }
                if let index = existing {
                    savedSamples[index] = sample
                } else {
                    savedSamples.append(sample)
                }
            }
        }
    }

    func startObserving(
        _ metrics: Set<HealthMetric>,
        onChange: @escaping HealthChangeHandler
    ) throws {
        try lock.withLock {
            guard config.available else { throw HealthStoreError.healthDataUnavailable }
            observing = metrics
            changeHandler = onChange
        }
    }

    func enableBackgroundDelivery(for metrics: Set<HealthMetric>) async throws {
        lock.withLock { backgroundDelivery = metrics }
    }

    func disableAllBackgroundDelivery() async throws {
        lock.withLock {
            backgroundDelivery = []
            observing = []
            changeHandler = nil
        }
    }

    private func samples(_ metric: HealthMetric, in interval: DateInterval) throws -> [QuantityRecord] {
        try lock.withLock {
            guard config.available else { throw HealthStoreError.healthDataUnavailable }
            guard !config.failingMetrics.contains(metric) else {
                throw HealthStoreError.queryFailed("fake failure: \(metric.rawValue)")
            }
            let samples = config.quantities[metric] ?? []
            return samples.filter { $0.start < interval.end && $0.end > interval.start }
        }
    }
}
