#if canImport(HealthKit)
import Foundation
import HealthKit

/// The real `HealthStore`, and the only type in this package that touches HealthKit.
///
/// Deliberately thin: it maps types and units, runs queries, and converts results into
/// the module's value types. Every decision worth testing — what an aggregation means,
/// how a mirror is keyed, when a write is idempotent — lives above it and is tested
/// against a fake. What cannot be tested off-device is exactly what is left here.
public final class HKHealthStoreAdapter: HealthStore, @unchecked Sendable {
    private let store: HKHealthStore
    /// Observer queries must outlive `startObserving`, so references are held here.
    /// Guarded by a lock because HealthKit calls back on its own queues.
    private let lock = NSLock()
    private var observers: [HKObserverQuery] = []

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    public func requestAuthorization(read: Set<HealthMetric>,
                                     write: Set<HealthWriteMetric>) async throws {
        try await store.requestAuthorization(toShare: shareTypes(write), read: readTypes(read))
    }

    public func writeStatus(for metric: HealthWriteMetric) -> WriteAuthorization {
        switch store.authorizationStatus(for: HKTypeMapping.quantityType(for: metric)) {
        case .sharingAuthorized: return .granted
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public func authorizationRequestStatus(
        read: Set<HealthMetric>,
        write: Set<HealthWriteMetric>
    ) async throws -> AuthorizationRequest {
        let status = try await store.statusForAuthorizationRequest(toShare: shareTypes(write),
                                                                   read: readTypes(read))
        switch status {
        case .shouldRequest: return .shouldRequest
        case .unnecessary: return .unnecessary
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    private func shareTypes(_ metrics: Set<HealthWriteMetric>) -> Set<HKSampleType> {
        Set(metrics.map { HKTypeMapping.quantityType(for: $0) as HKSampleType })
    }

    private func readTypes(_ metrics: Set<HealthMetric>) -> Set<HKObjectType> {
        Set(metrics.compactMap { HKTypeMapping.sampleType(for: $0) as HKObjectType? })
    }

    // MARK: - Reads

    public func statistic(_ metric: HealthMetric, in interval: DateInterval) async throws -> Double? {
        guard let type = HKTypeMapping.quantityType(for: metric),
              let unit = HKTypeMapping.unit(for: metric) else {
            throw HealthStoreError.unsupportedQuery(metric)
        }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate(interval)),
            options: HKTypeMapping.statisticsOptions(for: metric))
        do {
            guard let statistics = try await descriptor.result(for: store) else { return nil }
            let quantity: HKQuantity?
            switch metric.aggregation {
            case .cumulativeTotal: quantity = statistics.sumQuantity()
            case .dailyAverage: quantity = statistics.averageQuantity()
            default: quantity = statistics.mostRecentQuantity()
            }
            return quantity.map { $0.doubleValue(for: unit.unit) * unit.scale }
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    public func quantitySamples(_ metric: HealthMetric,
                                in interval: DateInterval) async throws -> [QuantityRecord] {
        guard let type = HKTypeMapping.quantityType(for: metric),
              let unit = HKTypeMapping.unit(for: metric) else {
            throw HealthStoreError.unsupportedQuery(metric)
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await descriptor.result(for: store).map { sample in
                QuantityRecord(
                    id: sample.uuid,
                    metric: metric,
                    value: sample.quantity.doubleValue(for: unit.unit) * unit.scale,
                    start: sample.startDate,
                    end: sample.endDate,
                    sourceName: sample.sourceRevision.source.name)
            }
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    public func categorySamples(_ metric: HealthMetric,
                                in interval: DateInterval) async throws -> [CategoryRecord] {
        guard let type = HKTypeMapping.categoryType(for: metric) else {
            throw HealthStoreError.unsupportedQuery(metric)
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await descriptor.result(for: store).map { sample in
                CategoryRecord(
                    id: sample.uuid,
                    metric: metric,
                    value: sample.value,
                    stage: metric == .sleepAnalysis
                        ? HKTypeMapping.stage(forSleepValue: sample.value)
                        : nil,
                    start: sample.startDate,
                    end: sample.endDate,
                    sourceName: sample.sourceRevision.source.name)
            }
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    public func workouts(in interval: DateInterval) async throws -> [WorkoutRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await descriptor.result(for: store).map(Self.record(from:))
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    /// Heart-rate samples inside the workout's own interval.
    ///
    /// Filtering by the workout's time range rather than by object association, because
    /// association is not guaranteed for every recording source while the interval always
    /// holds the session's beats.
    public func heartRateSeries(forWorkout id: UUID,
                                in interval: DateInterval) async throws -> [QuantityRecord] {
        try await quantitySamples(.heartRate, in: interval)
    }

    public func anchoredWorkouts(since anchor: HealthAnchorToken?) async throws -> AnchoredWorkouts {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout()],
            anchor: anchor.flatMap(Self.decodeAnchor))
        do {
            let result = try await descriptor.result(for: store)
            return AnchoredWorkouts(
                workouts: result.addedSamples.map(Self.record(from:)),
                deletedIds: result.deletedObjects.map(\.uuid),
                anchor: Self.encodeAnchor(result.newAnchor))
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    private func predicate(_ interval: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: interval.start, end: interval.end,
                                    options: [.strictStartDate])
    }

    private static func record(from workout: HKWorkout) -> WorkoutRecord {
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
        return WorkoutRecord(
            id: workout.uuid,
            activityType: HKTypeMapping.activityName(workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            activeEnergyKcal: energy,
            sourceName: workout.sourceRevision.source.name)
    }

    // MARK: - Writes

    public func save(_ samples: [WriteSample]) async throws {
        guard !samples.isEmpty else { return }
        let objects: [HKObject] = samples.map { sample in
            let type = HKTypeMapping.quantityType(for: sample.metric)
            let quantity = HKQuantity(unit: HKTypeMapping.unit(for: sample.metric),
                                      doubleValue: sample.value)
            // The sync identifier is what makes a retry replace rather than duplicate.
            // HealthKit requires a version alongside it.
            return HKQuantitySample(
                type: type, quantity: quantity, start: sample.start, end: sample.end,
                metadata: [
                    HKMetadataKeySyncIdentifier: sample.syncIdentifier,
                    HKMetadataKeySyncVersion: sample.syncVersion
                ])
        }
        do {
            try await store.save(objects)
        } catch {
            throw HealthStoreError.queryFailed(String(describing: error))
        }
    }

    // MARK: - Observers and background delivery

    public func startObserving(
        _ metrics: Set<HealthMetric>,
        onChange: @escaping HealthChangeHandler
    ) throws {
        var started: [HKObserverQuery] = []
        for metric in metrics.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let type = HKTypeMapping.sampleType(for: metric) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                // The completion handler must run even on error, or iOS stops delivering
                // updates for this type entirely.
                let receipt = ObserverReceipt(completion)
                guard error == nil else {
                    receipt.acknowledge()
                    return
                }
                onChange(metric) { receipt.acknowledge() }
            }
            store.execute(query)
            started.append(query)
        }
        lock.withLock { observers.append(contentsOf: started) }
    }

    public func enableBackgroundDelivery(for metrics: Set<HealthMetric>) async throws {
        for metric in metrics {
            guard let type = HKTypeMapping.sampleType(for: metric) else { continue }
            try await store.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
    }

    public func disableAllBackgroundDelivery() async throws {
        for query in takeObservers() { store.stop(query) }
        try await store.disableAllBackgroundDelivery()
    }

    /// Non-async on purpose: the lock may not be held across a suspension point.
    private func takeObservers() -> [HKObserverQuery] {
        lock.withLock {
            let running = observers
            observers = []
            return running
        }
    }

    private static func encodeAnchor(_ anchor: HKQueryAnchor) -> HealthAnchorToken? {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor,
                                                           requiringSecureCoding: true) else {
            return nil
        }
        return HealthAnchorToken(rawValue: data)
    }

    private static func decodeAnchor(_ token: HealthAnchorToken) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: token.rawValue)
    }
}

/// HealthKit's observer completion block is not `Sendable`, and it must be called exactly
/// once however the pass ends. Boxing it makes the hand-off explicit rather than implicit.
private final class ObserverReceipt: @unchecked Sendable {
    private let handler: HKObserverQueryCompletionHandler

    init(_ handler: @escaping HKObserverQueryCompletionHandler) {
        self.handler = handler
    }

    func acknowledge() { handler() }
}
#endif
