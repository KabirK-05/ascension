import AscensionCore
import Foundation
import Testing

@testable import SyncClient

/// ASC-27 — a Tier-2 write Apple Health would not take.
///
/// `HealthWriter` reports a refused scope in its receipt instead of throwing, which is right
/// for the Eat screen and was, for a while, read by this seam as success: the drain acked a
/// `log_meal` that had reached nothing, wrote the diary row anyway, and nothing ever retried
/// it. HealthKit is the source of truth (`docs/SPEC.md` §3), so these tests pin the two
/// halves of the fix — the write is retried while there is any hope, and the moment the
/// drain gives up the user is told rather than the failure being filed as a meal.
@Suite("ASC-27 — a write Apple Health refused")
struct RefusedHealthWriteTests {
    /// The meal sorts first, so the second mutation is behind it in the queue and a test can
    /// see whether a refused write holds the rest of the page hostage.
    private static let mealId = Fixture.Ulid.first
    private static let targetsId = Fixture.Ulid.second
    private static let waterId = Fixture.Ulid.third

    /// Every nutrition scope the meal needs, refused.
    private static let allNutrition = ["dietary_energy", "dietary_protein",
                                       "dietary_carbohydrates", "dietary_fat"]

    /// A drain that can be run more than once against the same page, which is what a retry
    /// is: the Worker keeps delivering a mutation nobody acked.
    ///
    /// Wired here rather than through `Fixture.drainer`, whose transport is concrete — this
    /// suite needs one that answers every pass, and widening another ticket's fixture to get
    /// it would be the larger change.
    private struct Kit {
        var drainer: MutationDrainer
        var transport: RepeatingTransport
        var local: RecordingLocalApplier
        var health: RecordingHealthWriteBack
        var state: InMemorySyncStateStore

        /// Every id this drain has acked, in the order it acked them.
        func ackedIds() throws -> [String] {
            try transport.ackBodies.flatMap {
                try JSONDecoder().decode(MutationAck.self, from: $0).ids
            }
        }
    }

    private func drainKit(_ mutations: [Mutation]) throws -> Kit {
        let transport = RepeatingTransport(page: try Fixture.mutationPage(mutations))
        let local = RecordingLocalApplier()
        let health = RecordingHealthWriteBack()
        let state = InMemorySyncStateStore()
        let session = SyncSession(transport: transport,
                                  tokens: InMemoryDeviceTokenStore(token: "device-token"),
                                  policy: .none, sleeper: RecordingSleeper())
        return Kit(drainer: MutationDrainer(
            session: session, endpoint: Fixture.origin,
            applier: MutationApplier(local: local, health: health, clock: Fixture.clock),
            state: state, clock: Fixture.clock),
                   transport: transport, local: local, health: health, state: state)
    }

    // MARK: - The bug, now the other way round

    @Test("a meal Apple Health refused is not acked, and gets no diary row")
    func aRefusedMealIsNotAcked() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId)])
        kit.health.refusedMetrics = Self.allNutrition

        let report = try await kit.drainer.drain()

        #expect(report.applied.isEmpty)
        #expect(report.blockedBy?.id == Self.mealId)
        #expect(report.blockedBy?.kind == .logMeal)
        // No local record of any sort: not a meal, and not yet a refusal either — the
        // mutation is still queued, so there is nothing final to tell the user.
        #expect(kit.local.log.isEmpty)
        #expect(kit.local.meals.isEmpty)
        #expect(kit.local.refusals.isEmpty)
        // Nothing acked at all, so the Worker delivers it again.
        #expect(try kit.ackedIds().isEmpty)
        #expect(report.cursor == nil)
    }

    @Test("the reason names the metrics Apple Health declined and the attempt")
    func theBlockedReasonIsSpecific() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId)])
        kit.health.refusedMetrics = ["dietary_energy", "dietary_protein"]

        let reason = try await #require(kit.drainer.drain().blockedBy?.reason)

        #expect(reason.contains("dietary_energy"))
        #expect(reason.contains("dietary_protein"))
        #expect(reason.contains("attempt 1 of 3"))
    }

    /// Half a meal in Apple Health is divergence just as much as none of it, and retrying is
    /// free: the sync identifier makes the second attempt a replacement.
    @Test("a partly written meal counts as refused, not as applied")
    func aPartialWriteIsNotSuccess() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId)])
        kit.health.grantedMetrics = ["dietary_energy", "dietary_protein"]
        kit.health.refusedMetrics = ["dietary_fat"]

        let report = try await kit.drainer.drain()

        #expect(report.applied.isEmpty)
        #expect(report.blockedBy?.id == Self.mealId)
        #expect(kit.local.meals.isEmpty)
    }

    // MARK: - Retry, and then the telling

    @Test("the refusal is retried, counted, and given up on at the third attempt")
    func theDrainGivesUpAtTheLimit() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId)])
        kit.health.refusedMetrics = Self.allNutrition

        #expect(try await kit.drainer.drain().blockedBy?.failureCount == 1)
        #expect(try await kit.drainer.drain().blockedBy?.failureCount == 2)
        #expect(try kit.state.load().failures[Self.mealId] == 2)

        // Third attempt: the drain stops retrying and reports instead.
        let third = try await kit.drainer.drain()

        #expect(third.applied == [Self.mealId])
        #expect(third.blockedBy == nil)
        #expect(try kit.ackedIds() == [Self.mealId])
        // The ledger stops counting a mutation it has finished with.
        #expect(try kit.state.load().failures[Self.mealId] == nil)
    }

    @Test("giving up records a refusal the user can see, and still no diary row")
    func givingUpRecordsTheRefusal() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId)])
        kit.health.refusedMetrics = Self.allNutrition

        for _ in 1...3 { _ = try? await kit.drainer.drain() }

        #expect(kit.local.log == ["refused_health_write:\(Self.mealId)"])
        #expect(kit.local.meals.isEmpty)
        let refusal = try #require(kit.local.refusals.first)
        #expect(refusal.attempts == 3)
        #expect(refusal.refusedMetrics == Self.allNutrition.sorted())
        guard case .meal(let payload) = refusal.subject else {
            Issue.record("a refused log_meal must carry the meal, not \(refusal.subject)")
            return
        }
        #expect(payload.meal == .lunch)
        #expect(payload.totals.kcal == 650)
    }

    /// The reason the limit exists at all. `MutationDrainer` stops the drain at a failure
    /// rather than skipping past it, so an unbounded retry on a scope the user has refused
    /// outright would hold every later mutation of Muse's behind it for good.
    @Test("a refused meal holds the page behind it, and lets it through once it gives up")
    func theQueueBehindItIsReleased() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId),
                               Fixture.setTargets(id: Self.targetsId, kcal: 2300)])
        kit.health.refusedMetrics = Self.allNutrition

        let first = try await kit.drainer.drain()
        #expect(first.applied.isEmpty)
        #expect(kit.local.targets.isEmpty)

        _ = try await kit.drainer.drain()
        #expect(kit.local.targets.isEmpty)

        let third = try await kit.drainer.drain()
        #expect(third.applied == [Self.mealId, Self.targetsId])
        #expect(kit.local.targets.count == 1)
    }

    /// The point of retrying rather than reporting straight away: the fix for a refused
    /// scope is in the user's hands, and when they grant it the meal must actually land.
    @Test("a scope granted before the limit writes the meal and records it normally")
    func grantingTheScopeRecoversTheMeal() async throws {
        let kit = try drainKit([Fixture.logMeal(id: Self.mealId)])
        kit.health.refusedMetrics = Self.allNutrition

        _ = try? await kit.drainer.drain()
        kit.health.refusedMetrics = []

        let second = try await kit.drainer.drain()

        #expect(second.applied == [Self.mealId])
        #expect(kit.local.log == ["log_meal:\(Self.mealId)"])
        #expect(kit.local.refusals.isEmpty)
        #expect(kit.local.meals.map(\.id) == [Self.mealId])
        #expect(kit.health.mealWrites(forEntry: Self.mealId).count == 2)
    }

    // MARK: - Water, which has nowhere else to live

    @Test("refused water is not acked either, and is reported when the drain gives up")
    func refusedWaterIsReported() async throws {
        let kit = try drainKit([Fixture.logWater(id: Self.waterId, ml: 400)])
        kit.health.refusedMetrics = ["dietary_water"]

        let first = try await kit.drainer.drain()
        #expect(first.applied.isEmpty)
        #expect(first.blockedBy?.kind == .logWater)
        #expect(try kit.ackedIds().isEmpty)

        _ = try? await kit.drainer.drain()
        let third = try await kit.drainer.drain()

        #expect(third.applied == [Self.waterId])
        let refusal = try #require(kit.local.refusals.first)
        #expect(refusal.refusedMetrics == ["dietary_water"])
        guard case .water(let millilitres) = refusal.subject else {
            Issue.record("a refused log_water must carry the volume, not \(refusal.subject)")
            return
        }
        #expect(millilitres == 400)
    }

    // MARK: - The outcome type

    @Test("an outcome that saved nothing has not reached everything, refusals or not")
    func anEmptyOutcomeIsNotSuccess() {
        #expect(HealthWriteOutcome(savedMetrics: ["dietary_energy"]).reachedEverything)
        #expect(!HealthWriteOutcome().reachedEverything)
        #expect(!HealthWriteOutcome(refusedMetrics: ["dietary_fat"]).reachedEverything)
        #expect(!HealthWriteOutcome(savedMetrics: ["dietary_energy"],
                                    refusedMetrics: ["dietary_fat"]).reachedEverything)
    }
}

/// A transport that answers every `GET /v1/mutations` with the same page, so one test can
/// drain repeatedly — which is what the Worker does with a mutation nobody acked.
final class RepeatingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let page: String
    private var recorded: [HTTPRequest] = []

    init(page: String) {
        self.page = page
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    /// The bodies of every ack this drain sent, in order.
    var ackBodies: [Data] {
        requests.filter { $0.url.path.hasSuffix("/mutations/ack") }.compactMap(\.body)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        let isAck = request.url.path.hasSuffix("/mutations/ack")
        return .json(isAck ? "{}" : page)
    }
}
