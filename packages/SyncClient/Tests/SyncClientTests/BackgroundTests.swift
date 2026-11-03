import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Background and push")
struct BackgroundTests {
    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    @Test("the task identifiers are the ones Project.swift permits")
    func identifiersMatchTheProject() {
        #expect(SyncTaskIdentifier.nightlyPush == "com.kabirkumar.ascension.nightly-export")
        #expect(SyncTaskIdentifier.mutationDrain == "com.kabirkumar.ascension.rollup-sync")
    }

    @Test("the nightly run is the next 03:00 local, strictly after now")
    func nightlyRunIsTheNextLocalHour() throws {
        let toronto = try zone("America/Toronto")
        let evening = try #require(Timestamp.literal("2026-11-03T23:05:00-05:00").date)
        let next = SyncSchedule.nextNightlyRun(after: evening, in: toronto)
        #expect(Timestamp(next, timeZone: toronto).rawValue == "2026-11-04T03:00:00-05:00")

        let smallHours = try #require(Timestamp.literal("2026-11-04T01:00:00-05:00").date)
        let sameMorning = SyncSchedule.nextNightlyRun(after: smallHours, in: toronto)
        #expect(Timestamp(sameMorning, timeZone: toronto).rawValue == "2026-11-04T03:00:00-05:00")

        // Exactly on the hour counts as past, so a run cannot schedule itself for now.
        let onTheHour = try #require(Timestamp.literal("2026-11-04T03:00:00-05:00").date)
        let tomorrow = SyncSchedule.nextNightlyRun(after: onTheHour, in: toronto)
        #expect(Timestamp(tomorrow, timeZone: toronto).rawValue == "2026-11-05T03:00:00-05:00")
    }

    @Test("the local hour holds across a DST change rather than drifting an hour")
    func nightlyRunHoldsTheLocalHourAcrossDST() throws {
        let toronto = try zone("America/Toronto")
        // Toronto falls back at 02:00 on 2026-11-01.
        let beforeFallBack = try #require(Timestamp.literal("2026-10-31T23:00:00-04:00").date)
        let after = SyncSchedule.nextNightlyRun(after: beforeFallBack, in: toronto)
        let stamped = Timestamp(after, timeZone: toronto).rawValue
        #expect(stamped == "2026-11-01T03:00:00-05:00")
        #expect(stamped.hasPrefix("2026-11-01T03:00"))
    }

    @Test("a silent push is only acted on when it is the Worker asking for a drain")
    func onlyTheWorkersPushDrains() {
        let ours: [AnyHashable: Any] = ["aps": ["content-available": 1],
                                        "ascension": ["reason": "mutations"]]
        #expect(SilentPushHandler.wantsDrain(userInfo: ours))
        #expect(!SilentPushHandler.wantsDrain(userInfo: ["aps": ["content-available": 1]]))
        #expect(!SilentPushHandler.wantsDrain(userInfo: ["ascension": ["reason": "something"]]))
        #expect(!SilentPushHandler.wantsDrain(userInfo: [:]))
    }

    @Test("a push that is not ours touches the network not at all")
    func foreignPushIsIgnored() async throws {
        let transport = FakeTransport(replies: [], fallback: .response(.json("{}")))
        let handler = SilentPushHandler(engine: engine(transport))
        let report = try await handler.handle(userInfo: ["aps": ["content-available": 1]])
        #expect(report == nil)
        #expect(transport.requestCount == 0)
    }

    @Test("the Worker's push drains, and the drain is the same one refresh runs")
    func pushDrains() async throws {
        let page = try Fixture.mutationPage([Fixture.setTargets(id: Fixture.Ulid.first,
                                                                kcal: 2300)])
        let transport = FakeTransport(replies: [.response(.json(page))],
                                      fallback: .response(.json(#"{"schemaVersion":1}"#)))
        let handler = SilentPushHandler(engine: engine(transport))
        let report = try await handler.handle(userInfo: ["aps": ["content-available": 1],
                                                         "ascension": ["reason": "mutations"]])
        #expect(report?.applied == [Fixture.Ulid.first])
    }

    @Test("an APNs token is formatted as lowercase hex")
    func apnsTokenIsHex() async {
        let token = Data([0x00, 0x0f, 0xab, 0xff])
        #expect(RemoteNotificationRegistrar.hex(token) == "000fabff")
    }

    @Test("the APNs token is handed to the app shell, not posted to an invented endpoint")
    func apnsTokenReachesTheHandler() async {
        let box = TokenBox()
        let registrar = RemoteNotificationRegistrar { token in await box.set(token) }
        await registrar.received(deviceToken: Data([0xde, 0xad, 0xbe, 0xef]))
        #expect(await box.value == "deadbeef")
    }

    @Test("a background drain reports failure instead of throwing out of the task")
    func backgroundDrainSwallowsAndReports() async throws {
        let transport = FakeTransport(replies: [.response(HTTPResponse(status: 500))])
        let coordinator = BackgroundSyncCoordinator(engine: engine(transport),
                                                    rollups: EmptyRollupSource(),
                                                    clock: Fixture.clock)
        #expect(await coordinator.runMutationDrain() == false)
    }

    @Test("the nightly job drains and then pushes, in that order")
    func nightlyJobDrainsThenPushes() async throws {
        let page = try Fixture.mutationPage([Fixture.setTargets(id: Fixture.Ulid.first,
                                                                kcal: 2300)])
        let transport = FakeTransport(replies: [
            .response(.json(page)),
            .response(.json(#"{"schemaVersion":1}"#)),
            .response(.json(Fixture.ingestReceipt))
        ])
        let coordinator = BackgroundSyncCoordinator(
            engine: engine(transport),
            rollups: FixedRollupSource(rollups: [Fixture.rollup]),
            clock: Fixture.clock)

        #expect(await coordinator.runNightlyPush())
        #expect(transport.requests.map(\.url.path)
            == ["/v1/mutations", "/v1/mutations/ack", "/v1/ingest"])
    }

    @Test("a blocked drain still lets the day's observations reach the cloud")
    func aBlockedDrainDoesNotStopThePush() async throws {
        let transport = FakeTransport(replies: [
            .response(HTTPResponse(status: 500)),
            .response(.json(Fixture.ingestReceipt))
        ])
        let engine = engine(transport)
        await #expect(throws: SyncError.self) {
            try await engine.syncNow(rollups: [Fixture.rollup])
        }
        #expect(transport.requests.map(\.url.path) == ["/v1/mutations", "/v1/ingest"])
    }

    private func engine(_ transport: FakeTransport) -> SyncEngine {
        SyncEngine.live(origin: Fixture.origin,
                        tokens: InMemoryDeviceTokenStore(token: "device-token-for-tests"),
                        local: RecordingLocalApplier(),
                        health: RecordingHealthWriteBack(),
                        state: InMemorySyncStateStore(),
                        clock: Fixture.clock,
                        transport: transport,
                        policy: .none)
    }
}

private actor TokenBox {
    private(set) var value: String?

    func set(_ token: String) {
        value = token
    }
}

private struct EmptyRollupSource: RollupSource {
    func rollupsToPush() async throws -> [DayRollup] { [] }
}

private struct FixedRollupSource: RollupSource {
    let rollups: [DayRollup]

    func rollupsToPush() async throws -> [DayRollup] { rollups }
}
