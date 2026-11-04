import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Mutation drain — pull, apply, ack")
struct MutationDrainTests {
    /// A drain whose first reply is `page` and whose later replies (the ack) all succeed.
    private func harness(page: String,
                         state: any SyncStateStore = InMemorySyncStateStore()) -> DrainHarness {
        let transport = FakeTransport(replies: [.response(.json(page))],
                                      fallback: .response(.json(#"{"schemaVersion":1}"#)))
        let local = RecordingLocalApplier()
        let health = RecordingHealthWriteBack()
        return DrainHarness(
            drainer: Fixture.drainer(transport: transport, state: state,
                                     local: local, health: health),
            transport: transport, local: local, health: health, state: state)
    }

    @Test("mutations apply in id order, however the page arrives")
    func appliesInIdOrder() async throws {
        let page = try Fixture.mutationPage([
            Fixture.logTopSet(id: Fixture.Ulid.third),
            Fixture.setTargets(id: Fixture.Ulid.first, kcal: 2300),
            Fixture.logWater(id: Fixture.Ulid.second)
        ])
        let kit = harness(page: page)
        let report = try await kit.drainer.drain()

        #expect(report.applied == [Fixture.Ulid.first, Fixture.Ulid.second, Fixture.Ulid.third])
        #expect(kit.local.log == ["set_targets:\(Fixture.Ulid.first)",
                                  "log_top_set:\(Fixture.Ulid.third)"])
        #expect(kit.health.waters.map(\.entryId) == [Fixture.Ulid.second])
    }

    @Test("the fetch sends the stored cursor as ?since=, and no cursor on a fresh install")
    func fetchUsesTheStoredCursor() async throws {
        let fresh = harness(page: try Fixture.mutationPage([]))
        _ = try await fresh.drainer.drain()
        #expect(fresh.transport.requests.first?.url.query == nil)

        let store = InMemorySyncStateStore(state: SyncState(cursor: Fixture.Ulid.first))
        let resumed = harness(page: try Fixture.mutationPage([]), state: store)
        _ = try await resumed.drainer.drain()
        #expect(resumed.transport.requests.first?.url.query == "since=\(Fixture.Ulid.first)")
    }

    @Test("only what applied is acked, with the instant the device applied it")
    func ackCarriesTheAppliedIds() async throws {
        let page = try Fixture.mutationPage([Fixture.setTargets(id: Fixture.Ulid.first,
                                                                kcal: 2300)])
        let kit = harness(page: page)
        _ = try await kit.drainer.drain()

        #expect(kit.transport.requestCount == 2)
        let ack = kit.transport.requests[1]
        #expect(ack.method == .post)
        #expect(ack.url.path == "/v1/mutations/ack")
        let body = try #require(ack.body)
        let decoded = try SyncCoding.decoder().decode(MutationAck.self, from: body)
        #expect(decoded.ids == [Fixture.Ulid.first])
        #expect(decoded.appliedAt.rawValue == "2026-11-03T23:05:00-05:00")
        #expect(decoded.schemaVersion == 1)
    }

    @Test("a duplicate delivery applies once — and is acked again, so it stops arriving")
    func duplicateDeliveryAppliesOnce() async throws {
        let state = InMemorySyncStateStore()
        let meal = Fixture.logMeal(id: Fixture.Ulid.first)

        let first = harness(page: try Fixture.mutationPage([meal]), state: state)
        let firstReport = try await first.drainer.drain()
        #expect(firstReport.applied == [Fixture.Ulid.first])
        #expect(first.health.mealWrites(forEntry: Fixture.Ulid.first).count == 1)

        // The same mutation again: the Worker re-sent it because an ack was lost.
        let again = harness(page: try Fixture.mutationPage([meal]), state: state)
        let secondReport = try await again.drainer.drain()

        #expect(secondReport.applied.isEmpty)
        #expect(secondReport.alreadyApplied == [Fixture.Ulid.first])
        #expect(again.health.meals.isEmpty, "the second delivery must not write to Health")
        #expect(again.local.log.isEmpty)
        // Still acked, otherwise it would be delivered forever.
        #expect(again.transport.requestCount == 2)
    }

    @Test("a Tier-2 meal applied twice writes to Apple Health once")
    func tierTwoMealIsIdempotent() async throws {
        let state = InMemorySyncStateStore()
        let health = RecordingHealthWriteBack()
        let local = RecordingLocalApplier()
        let page = try Fixture.mutationPage([Fixture.logMeal(id: Fixture.Ulid.first)])

        for _ in 0..<2 {
            let transport = FakeTransport(replies: [.response(.json(page))],
                                          fallback: .response(.json(#"{"schemaVersion":1}"#)))
            let drainer = Fixture.drainer(transport: transport, state: state,
                                          local: local, health: health)
            _ = try await drainer.drain()
        }

        #expect(health.meals.count == 1)
        #expect(local.meals.count == 1)
        // The entry id is the mutation's ULID: HealthBridge turns it into the HealthKit
        // sync identifier, which is the second line of defence if the ledger is ever lost.
        #expect(health.meals.first?.entryId == Fixture.Ulid.first)
        let logged = try #require(local.meals.first)
        #expect(logged.id == Fixture.Ulid.first)
        #expect(logged.slot == .lunch)
        #expect(logged.kcal == 650)
        #expect(logged.proteinG == 55)
    }

    @Test("a meal is stamped inside its own local day, at the slot's hour")
    func mealInstantLandsInTheRightDay() throws {
        let zone = try #require(TimeZone(identifier: Fixture.timezone))
        let instant = MutationApplier.instant(for: CalendarDate.literal("2026-11-03"),
                                              kind: .dinner, timeZone: zone)
        #expect(Timestamp(instant, timeZone: zone).rawValue == "2026-11-03T19:00:00-05:00")

        let bare = MutationApplier.instant(for: CalendarDate.literal("2026-11-03"),
                                           kind: nil, timeZone: zone)
        #expect(Timestamp(bare, timeZone: zone).rawValue == "2026-11-03T12:00:00-05:00")
    }

    @Test("a failing mutation stops the drain there; the ones after it stay queued")
    func failureBlocksRatherThanSkips() async throws {
        let state = InMemorySyncStateStore()
        let transport = FakeTransport(
            replies: [.response(.json(try Fixture.mutationPage([
                Fixture.setTargets(id: Fixture.Ulid.first, kcal: 2300),
                Fixture.logMeal(id: Fixture.Ulid.second),
                Fixture.logTopSet(id: Fixture.Ulid.third)
            ])))],
            fallback: .response(.json(#"{"schemaVersion":1}"#)))
        let local = RecordingLocalApplier()
        let health = RecordingHealthWriteBack()
        health.failure = TestFailure(description: "HealthKit refused the write")
        let drainer = Fixture.drainer(transport: transport, state: state,
                                      local: local, health: health)

        let report = try await drainer.drain()

        #expect(report.applied == [Fixture.Ulid.first])
        let blocked = try #require(report.blockedBy)
        #expect(blocked.id == Fixture.Ulid.second)
        #expect(blocked.kind == .logMeal)
        #expect(blocked.failureCount == 1)
        #expect(blocked.reason.contains("HealthKit refused"))
        // The third never ran: applying a later write over a failed earlier one would
        // leave Muse's intent half-applied and out of order.
        #expect(local.log == ["set_targets:\(Fixture.Ulid.first)"])
        // And the cursor stopped short of the failure.
        #expect(report.cursor == Fixture.Ulid.first)
        #expect(try state.load().failures[Fixture.Ulid.second] == 1)
    }

    @Test("a repeated failure is counted, so a poison pill is visible rather than silent")
    func failuresAreCounted() async throws {
        let state = InMemorySyncStateStore()
        for _ in 0..<2 {
            let transport = FakeTransport(
                replies: [.response(.json(try Fixture.mutationPage([
                    Fixture.logMeal(id: Fixture.Ulid.first)
                ])))],
                fallback: .response(.json(#"{"schemaVersion":1}"#)))
            let health = RecordingHealthWriteBack()
            health.failure = TestFailure(description: "still refused")
            let drainer = Fixture.drainer(transport: transport, state: state,
                                          local: RecordingLocalApplier(), health: health)
            _ = try await drainer.drain()
        }
        #expect(try state.load().failures[Fixture.Ulid.first] == 2)
        #expect(try state.load().cursor == nil)
    }

    @Test("every mutation kind routes to the right sink")
    func everyKindRoutes() async throws {
        let payloads: [Mutation] = [
            Fixture.mutation(id: Fixture.Ulid.first, kind: .setFlag,
                             payload: .object(["key": .string("museWritesEnabled"),
                                               "value": .bool(true)])),
            Fixture.mutation(id: Fixture.Ulid.second, kind: .acceptSuggestion,
                             payload: .object(["suggestionId": .string("sug_1")])),
            Fixture.mutation(id: Fixture.Ulid.third, kind: .triggerExport, payload: .object([:]))
        ]
        let kit = harness(page: try Fixture.mutationPage(payloads))
        _ = try await kit.drainer.drain()
        #expect(kit.local.log == ["set_flag:\(Fixture.Ulid.first)",
                                  "accept_suggestion:\(Fixture.Ulid.second)",
                                  "trigger_export:\(Fixture.Ulid.third)"])
    }

    @Test("a payload that has drifted from the contract fails loudly, applying nothing")
    func driftedPayloadFails() async throws {
        let bad = Fixture.mutation(id: Fixture.Ulid.first, kind: .logTopSet,
                                   payload: .object(["date": .string("2026-11-03"),
                                                     "exercise": .string("Goblet_Squat")]))
        let kit = harness(page: try Fixture.mutationPage([bad]))
        let report = try await kit.drainer.drain()
        #expect(report.applied.isEmpty)
        #expect(report.blockedBy?.id == Fixture.Ulid.first)
        #expect(kit.local.log.isEmpty)
    }

    @Test("a bare array of mutations decodes too, as the ingest endpoint also allows")
    func bareArrayDecodes() async throws {
        let mutation = Fixture.setTargets(id: Fixture.Ulid.first, kcal: 2300)
        let array = try Golden.pretty([mutation])
        let kit = harness(page: array)
        let report = try await kit.drainer.drain()
        #expect(report.applied == [Fixture.Ulid.first])
    }

    @Test("set_targets patches only the fields Muse sent")
    func targetsPatchIsPartial() async throws {
        let kit = harness(page: try Fixture.mutationPage([
            Fixture.setTargets(id: Fixture.Ulid.first, kcal: 2300)
        ]))
        _ = try await kit.drainer.drain()
        let patch = try #require(kit.local.targets.first)
        #expect(patch.kcal == 2300)
        #expect(patch.proteinG == nil)
        let applied = patch.applied(to: Fixture.goals.targets)
        #expect(applied.kcal == 2300)
        #expect(applied.proteinMinG == 140)
        #expect(applied.fatMinG == 60)
    }
}

/// A drainer wired to recording sinks, so a test can assert on all three at once.
struct DrainHarness {
    var drainer: MutationDrainer
    var transport: FakeTransport
    var local: RecordingLocalApplier
    var health: RecordingHealthWriteBack
    var state: any SyncStateStore
}
