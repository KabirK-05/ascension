import AscensionCore
import Foundation

/// What one incremental pass found: rows to upsert, and workouts HealthKit no longer has.
public struct MirrorDelta: Hashable, Sendable {
    public var mirrors: MirrorSet
    public var deletedWorkoutIds: Set<String>

    public init(mirrors: MirrorSet = MirrorSet(), deletedWorkoutIds: Set<String> = []) {
        self.mirrors = mirrors
        self.deletedWorkoutIds = deletedWorkoutIds
    }

    public var isEmpty: Bool { mirrors.isEmpty && deletedWorkoutIds.isEmpty }
}

/// The module's front door: authorization, reads, mirrors, observers and the write-back.
///
/// An actor because the observer callbacks arrive on HealthKit's queues and the anchored
/// pass mutates a shared resume point. Composition only — the logic lives in the pieces
/// this assembles, which is what lets all of it be tested without a HealthKit store.
public actor HealthBridgeService {
    private let store: any HealthStore
    private let syncState: any HealthSyncState
    private let registry: HealthObserverRegistry
    private let authorization: HealthAuthorizationCoordinator
    public let reader: HealthReader
    public let writer: HealthWriter

    public init(store: any HealthStore,
                timeZone: TimeZone = HealthReader.defaultTimeZone,
                zones: HeartRateZones? = nil,
                syncState: any HealthSyncState = InMemorySyncState(),
                observedMetrics: Set<HealthMetric> = HealthMetric.backgroundDelivered) {
        self.store = store
        self.syncState = syncState
        self.reader = HealthReader(store: store, timeZone: timeZone, zones: zones)
        self.writer = HealthWriter(store: store)
        self.registry = HealthObserverRegistry(store: store, metrics: observedMetrics)
        self.authorization = HealthAuthorizationCoordinator(store: store)
    }

    // MARK: - Authorization

    /// Presents the system sheet if anything is outstanding. Safe on every launch.
    public func requestAuthorization() async throws -> HealthAuthorizationReport {
        try await authorization.requestAuthorization()
    }

    public func authorizationReport() async -> HealthAuthorizationReport {
        await authorization.report()
    }

    // MARK: - Reads

    public func snapshot(for date: CalendarDate) async -> DayHealthSnapshot {
        await reader.snapshot(for: date)
    }

    public func mirrors(in interval: DateInterval) async throws -> MirrorSet {
        try await reader.mirrors(in: interval)
    }

    // MARK: - Writes

    @discardableResult
    public func write(_ entry: NutritionEntry) async throws -> HealthWriteReceipt {
        try await writer.write(entry)
    }

    @discardableResult
    public func write(_ entry: BodyMeasurementEntry) async throws -> HealthWriteReceipt {
        try await writer.write(entry)
    }

    // MARK: - Observers

    /// Starts observer queries and background delivery, calling `onDelta` each time a
    /// pass finds something.
    ///
    /// `onDelta` may be called for data it has already seen — that is the framework's
    /// behaviour, not a bug to be hidden — so it must upsert, which `MirrorSet.merging`
    /// does.
    public func startObserving(
        onDelta: @escaping @Sendable (HealthMetric, MirrorDelta) async -> Void
    ) async throws {
        try await registry.start { [weak self] metric in
            guard let self else { return }
            let delta = (try? await self.incrementalPass(for: metric)) ?? MirrorDelta()
            guard !delta.isEmpty else { return }
            await onDelta(metric, delta)
        }
    }

    public func stopObserving() async throws {
        try await registry.stop()
    }

    /// Hands a change notification to the registry by hand, which is what a background
    /// task or a pull-to-refresh does.
    public func notifyChanged(_ metric: HealthMetric) async {
        await registry.changed(metric)
    }

    // MARK: - Incremental passes

    /// Reads only what changed since the last pass for this metric.
    ///
    /// Two layers of idempotency, because one is not enough: the anchor means HealthKit
    /// returns nothing the second time, and the seen-sample ledger means a reset anchor
    /// still does not reprocess a sample. If both are defeated, the mirrors upsert on
    /// UUID and the rows come out identical anyway.
    public func incrementalPass(for metric: HealthMetric) async throws -> MirrorDelta {
        switch metric {
        case .workouts:
            return try await workoutPass()
        case .sleepAnalysis, .bodyMass:
            return try await recentWindowPass()
        default:
            // Energy, steps and heart rate change the day's numbers, not the mirrors.
            // The caller re-reads the snapshot; there is nothing to upsert here.
            return MirrorDelta()
        }
    }

    private func workoutPass() async throws -> MirrorDelta {
        let anchor = await syncState.anchor(for: .workouts)
        let page = try await store.anchoredWorkouts(since: anchor)
        await syncState.setAnchor(page.anchor, for: .workouts)
        await syncState.forget(page.deletedIds, for: .workouts)

        let fresh = await syncState.admit(page.workouts.map(\.id), for: .workouts)
        let freshIds = Set(fresh)
        let records = page.workouts.filter { freshIds.contains($0.id) }
        var series: [UUID: [QuantityRecord]] = [:]
        for record in records {
            series[record.id] = try await store.heartRateSeries(forWorkout: record.id,
                                                                in: record.interval)
        }
        let mirrors = WorkoutMirrorBuilder.mirrors(from: records,
                                                   heartRateSeries: series,
                                                   zones: reader.zones)
        return MirrorDelta(mirrors: MirrorSet(workouts: mirrors),
                           deletedWorkoutIds: Set(page.deletedIds.map(\.uuidString)))
    }

    /// Sleep and weight are cheap to rebuild and arrive edited as often as they arrive
    /// new, so a short rolling window is re-derived rather than anchored. Every row
    /// upserts on its date, so re-deriving changes nothing that has not changed.
    private func recentWindowPass(days: Int = 3) async throws -> MirrorDelta {
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-Double(days) * 86_400), end: now)
        let sleepRecords = try await store.categorySamples(.sleepAnalysis, in: window)
        let weightRecords = try await store.quantitySamples(.bodyMass, in: window)
        let mirrors = MirrorSet(
            nights: SleepNightBuilder.nights(from: sleepRecords, timeZone: reader.timeZone),
            weights: WeightPointBuilder.points(from: weightRecords, timeZone: reader.timeZone))
        return MirrorDelta(mirrors: mirrors)
    }
}
