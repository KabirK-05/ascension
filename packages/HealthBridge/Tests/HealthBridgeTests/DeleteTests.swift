import Foundation
import Testing

@testable import HealthBridge

/// A deletable store that records what it was asked to remove.
///
/// Separate from `FakeHealthStore` on purpose: `HealthSampleDeleting` is its own seam
/// (see `HealthDeleter`), and a double for it needs nothing else from HealthKit.
final class FakeDeletableStore: HealthSampleDeleting, @unchecked Sendable {
    struct Request: Hashable {
        let metric: HealthWriteMetric
        let syncIdentifiers: Set<String>
    }

    private let lock = NSLock()
    private var held: [HealthWriteMetric: Set<String>]
    private var asked: [Request] = []

    let isHealthDataAvailable: Bool
    private let authorization: [HealthWriteMetric: WriteAuthorization]
    private let failure: (any Error)?

    init(holding: [HealthWriteMetric: Set<String>] = [:],
         available: Bool = true,
         authorization: [HealthWriteMetric: WriteAuthorization] = [:],
         failure: (any Error)? = nil) {
        self.held = holding
        self.isHealthDataAvailable = available
        self.authorization = authorization
        self.failure = failure
    }

    var requests: [Request] { lock.withLock { asked } }

    func remaining(_ metric: HealthWriteMetric) -> Set<String> {
        lock.withLock { held[metric] ?? [] }
    }

    func writeStatus(for metric: HealthWriteMetric) -> WriteAuthorization {
        authorization[metric] ?? .granted
    }

    func deleteSamples(metric: HealthWriteMetric,
                       syncIdentifiers: Set<String>) async throws -> Int {
        if let failure { throw failure }
        return lock.withLock {
            asked.append(Request(metric: metric, syncIdentifiers: syncIdentifiers))
            let matched = (held[metric] ?? []).intersection(syncIdentifiers)
            held[metric] = (held[metric] ?? []).subtracting(syncIdentifiers)
            return matched.count
        }
    }
}

@Suite("Health delete")
struct DeleteTests {

    private func identifiers(for entryId: String) -> [HealthWriteMetric: Set<String>] {
        var held: [HealthWriteMetric: Set<String>] = [:]
        for metric in HealthWriteMetric.nutrition {
            held[metric] = [HealthSampleFactory.syncIdentifier(entryId: entryId, metric: metric)]
        }
        return held
    }

    @Test("a meal's four samples go, found by the identifier the writer used")
    func removesTheSamplesTheWriterWrote() async throws {
        let store = FakeDeletableStore(holding: identifiers(for: "meal-1"))
        let receipt = try await HealthDeleter(store: store).delete(entryId: "meal-1")

        #expect(receipt.removedCount == 4)
        #expect(receipt.didReachEveryMetric)
        for metric in HealthWriteMetric.nutrition {
            #expect(store.remaining(metric).isEmpty)
        }
    }

    @Test("the identifiers asked for are exactly the writer's, not a timestamp guess")
    func asksForTheWritersIdentifiers() async throws {
        let store = FakeDeletableStore(holding: identifiers(for: "meal-1"))
        _ = try await HealthDeleter(store: store).delete(entryId: "meal-1")

        let asked = Set(store.requests.flatMap(\.syncIdentifiers))
        let expected = Set(HealthWriteMetric.nutrition.map {
            HealthSampleFactory.syncIdentifier(entryId: "meal-1", metric: $0)
        })
        #expect(asked == expected)
    }

    @Test("another meal's samples are left alone")
    func leavesOtherEntriesAlone() async throws {
        var holding = identifiers(for: "meal-1")
        for (metric, ids) in identifiers(for: "meal-2") {
            holding[metric, default: []].formUnion(ids)
        }
        let store = FakeDeletableStore(holding: holding)
        _ = try await HealthDeleter(store: store).delete(entryId: "meal-1")

        #expect(store.remaining(.dietaryProtein) ==
            [HealthSampleFactory.syncIdentifier(entryId: "meal-2", metric: .dietaryProtein)])
    }

    @Test("water is not part of a meal, so a meal delete never touches it")
    func leavesWaterAlone() async throws {
        let store = FakeDeletableStore(holding: [
            .dietaryWater: [HealthSampleFactory.syncIdentifier(entryId: "meal-1",
                                                               metric: .dietaryWater)]
        ])
        _ = try await HealthDeleter(store: store).delete(entryId: "meal-1")

        #expect(store.remaining(.dietaryWater).count == 1)
        #expect(store.requests.allSatisfy { $0.metric != .dietaryWater })
    }

    @Test("an id HealthKit never saw is already in the state the caller asked for")
    func deletingNothingSucceeds() async throws {
        let store = FakeDeletableStore()
        let receipt = try await HealthDeleter(store: store).delete(entryId: "never-written")

        #expect(receipt.removedCount == 0)
        #expect(receipt.didReachEveryMetric)
        #expect(!receipt.reachedNothing)
    }

    @Test("a refused scope is reported, and the scopes that were granted still go")
    func reportsRefusedScopes() async throws {
        let store = FakeDeletableStore(holding: identifiers(for: "meal-1"),
                                       authorization: [.dietaryFat: .denied])
        let receipt = try await HealthDeleter(store: store).delete(entryId: "meal-1")

        #expect(receipt.skipped[.dietaryFat] == .denied)
        #expect(!receipt.didReachEveryMetric)
        #expect(receipt.removedCount == 3)
        #expect(store.remaining(.dietaryFat).count == 1)
    }

    @Test("every scope refused reads as reaching nothing")
    func reportsReachingNothing() async throws {
        let denied = Dictionary(uniqueKeysWithValues:
            HealthWriteMetric.nutrition.map { ($0, WriteAuthorization.denied) })
        let store = FakeDeletableStore(holding: identifiers(for: "meal-1"),
                                       authorization: denied)
        let receipt = try await HealthDeleter(store: store).delete(entryId: "meal-1")

        #expect(receipt.reachedNothing)
        #expect(store.requests.isEmpty)
    }

    @Test("no HealthKit on this device throws rather than reporting a clean delete")
    func throwsWithoutHealthKit() async {
        let store = FakeDeletableStore(available: false)
        await #expect(throws: HealthStoreError.healthDataUnavailable) {
            try await HealthDeleter(store: store).delete(entryId: "meal-1")
        }
    }

    @Test("a store failure propagates — the caller must not drop its local row")
    func propagatesStoreFailure() async {
        let store = FakeDeletableStore(holding: identifiers(for: "meal-1"),
                                       failure: HealthStoreError.queryFailed("boom"))
        await #expect(throws: HealthStoreError.queryFailed("boom")) {
            try await HealthDeleter(store: store).delete(entryId: "meal-1")
        }
    }
}
