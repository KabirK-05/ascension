import Foundation
import Testing

@testable import HealthBridge

@Suite("observer callbacks are idempotent and always acknowledged")
struct ObserverPassTests {
    @Test("the anchored pass returns a workout once, not on every callback")
    func anchoredPassDeliversOnce() async throws {
        let store = FakeHealthStore()
        store.update { config in
            config.workouts = [Fixture.workout("upper-a", start: Fixture.instant(hour: 19), minutes: 51)]
        }
        let service = HealthBridgeService(store: store, timeZone: Fixture.timeZone,
                                          zones: Fixture.zones)

        let first = try await service.incrementalPass(for: .workouts)
        let second = try await service.incrementalPass(for: .workouts)
        let third = try await service.incrementalPass(for: .workouts)

        #expect(first.mirrors.workouts.count == 1)
        #expect(second.isEmpty)
        #expect(third.isEmpty)
    }

    @Test("a reset anchor still does not reprocess a sample the ledger has seen")
    func ledgerCatchesAResetAnchor() async throws {
        let store = FakeHealthStore()
        store.update { config in
            config.workouts = [Fixture.workout("upper-a", start: Fixture.instant(hour: 19), minutes: 51)]
        }
        let state = InMemorySyncState()
        let service = HealthBridgeService(store: store, timeZone: Fixture.timeZone,
                                          zones: Fixture.zones, syncState: state)

        let first = try await service.incrementalPass(for: .workouts)
        #expect(first.mirrors.workouts.count == 1)

        // Simulate the anchor being lost — a reinstall, or a defaults blob that failed to
        // decode. HealthKit then hands the same workout back.
        await state.setAnchor(nil, for: .workouts)
        let second = try await service.incrementalPass(for: .workouts)
        #expect(second.isEmpty)
    }

    @Test("a deletion is reported and lets the sample be processed again")
    func deletionsClearTheLedger() async throws {
        let store = FakeHealthStore()
        let workout = Fixture.workout("upper-a", start: Fixture.instant(hour: 19), minutes: 51)
        store.update { $0.workouts = [workout] }
        let service = HealthBridgeService(store: store, timeZone: Fixture.timeZone,
                                          zones: Fixture.zones)
        _ = try await service.incrementalPass(for: .workouts)

        store.queueDeletions([workout.id])
        let deletion = try await service.incrementalPass(for: .workouts)
        #expect(deletion.deletedWorkoutIds == [workout.id.uuidString])
    }

    @Test("the registry acknowledges every callback, which is what iOS requires")
    func callbacksAreAcknowledged() async throws {
        let store = FakeHealthStore()
        store.update { config in
            config.workouts = [Fixture.workout("upper-a", start: Fixture.instant(hour: 19), minutes: 51)]
        }
        let service = HealthBridgeService(store: store, timeZone: Fixture.timeZone,
                                          zones: Fixture.zones)
        try await service.startObserving { _, _ in }

        #expect(await store.fireObserver(.workouts))
        #expect(await store.fireObserver(.workouts))
    }

    @Test("background delivery is requested for exactly the metrics spec §6 stars")
    func backgroundDeliveryCoversTheStarredMetrics() async throws {
        let store = FakeHealthStore()
        let service = HealthBridgeService(store: store)
        try await service.startObserving { _, _ in }

        #expect(store.observedMetrics == HealthMetric.backgroundDelivered)
        #expect(store.backgroundDeliveryMetrics == HealthMetric.backgroundDelivered)
        #expect(store.backgroundDeliveryMetrics.count == 7)

        try await service.stopObserving()
        #expect(store.backgroundDeliveryMetrics.isEmpty)
    }

    @Test("starting observers without HealthKit fails instead of looking registered")
    func unavailableStoreRefusesToObserve() async {
        let store = FakeHealthStore(config: .init(available: false))
        let service = HealthBridgeService(store: store)
        await #expect(throws: HealthStoreError.healthDataUnavailable) {
            try await service.startObserving { _, _ in }
        }
    }

    @Test("three notifications during one pass produce one more pass, not three")
    func coalescerQueuesAtMostOneRerun() {
        var coalescer = ObserverCoalescer()
        #expect(coalescer.admit(.workouts) == .start)
        #expect(coalescer.admit(.workouts) == .queued)
        #expect(coalescer.admit(.workouts) == .queued)
        #expect(coalescer.admit(.workouts) == .queued)

        let rerun = coalescer.finish(.workouts)
        let second = coalescer.finish(.workouts)
        #expect(rerun)
        #expect(second == false)
        #expect(coalescer.isRunning(.workouts) == false)
    }

    @Test("the ledger admits an id once and bounds what it remembers")
    func ledgerAdmitsOnce() {
        var ledger = IdempotencyLedger(capacity: 3)
        let ids = (0..<4).map { Fixture.id("sample-\($0)") }

        #expect(ledger.admit([ids[0], ids[1]]).count == 2)
        #expect(ledger.admit([ids[0], ids[1]]).isEmpty)
        #expect(ledger.admit([ids[1], ids[2], ids[2]]) == [ids[2]])

        // Capacity 3: admitting a fourth id drops the oldest, which may then be admitted
        // again. The mirrors' upsert-on-UUID is what keeps that harmless.
        #expect(ledger.admit([ids[3]]) == [ids[3]])
        #expect(ledger.contains(ids[0]) == false)
        #expect(ledger.contains(ids[3]))
    }

    @Test("forgetting an id lets it be processed again")
    func ledgerForgets() {
        var ledger = IdempotencyLedger()
        let id = Fixture.id("sample")
        #expect(ledger.admit([id]) == [id])
        ledger.forget([id])
        #expect(ledger.admit([id]) == [id])
    }
}
