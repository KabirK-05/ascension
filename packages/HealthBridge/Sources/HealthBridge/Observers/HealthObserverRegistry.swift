import Foundation

/// Observer queries plus background delivery for the metrics spec §6 stars.
///
/// Two rules the framework enforces and this type honours:
///
/// 1. **The completion handler must always be called**, success or failure. iOS stops
///    delivering updates for a type whose handler went unanswered, and the app then looks
///    like it simply never notices new workouts.
/// 2. **Callbacks are not one-per-change.** The same change is delivered more than once,
///    and registration itself fires one immediately. Every handler here must therefore be
///    idempotent; the anchored reads and the mirrors' upsert-on-UUID are what make it so.
public actor HealthObserverRegistry {
    public typealias Handler = @Sendable (HealthMetric) async -> Void

    private let store: any HealthStore
    private let metrics: Set<HealthMetric>
    private var coalescer = ObserverCoalescer()
    private var handler: Handler?
    private var isStarted = false

    public init(store: any HealthStore,
                metrics: Set<HealthMetric> = HealthMetric.backgroundDelivered) {
        self.store = store
        self.metrics = metrics
    }

    /// Registers the observers and asks iOS for background delivery.
    ///
    /// Background delivery additionally needs the
    /// `com.apple.developer.healthkit.background-delivery` entitlement, which the app
    /// target carries in `app/Ascension.entitlements`, and the observers must be
    /// registered on every launch — including a launch iOS performed in the background —
    /// or the wake arrives with nothing listening.
    public func start(handler: @escaping Handler) async throws {
        guard store.isHealthDataAvailable else { throw HealthStoreError.healthDataUnavailable }
        self.handler = handler
        guard !isStarted else { return }

        try store.startObserving(metrics) { [weak self] metric, completion in
            // The completion block is handed straight through to the pass so it is called
            // exactly once, after the work, however the work ends.
            Task { [weak self] in
                await self?.changed(metric)
                completion()
            }
        }
        try await store.enableBackgroundDelivery(for: metrics.filter(\.wantsBackgroundDelivery))
        isStarted = true
    }

    public func stop() async throws {
        handler = nil
        isStarted = false
        try await store.disableAllBackgroundDelivery()
    }

    /// One change notification. Safe to call repeatedly for the same data: that is the
    /// contract the framework imposes, so it is the contract this honours.
    public func changed(_ metric: HealthMetric) async {
        guard metrics.contains(metric) else { return }
        guard coalescer.admit(metric) == .start else { return }
        repeat {
            await handler?(metric)
        } while coalescer.finish(metric)
    }
}
