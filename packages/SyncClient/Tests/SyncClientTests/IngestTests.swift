import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Ingest — POST /v1/ingest")
struct IngestTests {
    private func pusher(_ transport: FakeTransport, batchSize: Int = RollupPusher.maxBatchSize,
                        policy: RetryPolicy = .none,
                        sleeper: any Sleeper = RecordingSleeper()) -> RollupPusher {
        RollupPusher(session: Fixture.session(transport, policy: policy, sleeper: sleeper),
                     endpoint: Fixture.origin, batchSize: batchSize)
    }

    @Test("the device token rides as a bearer header, read from the store")
    func tokenIsABearerHeader() async throws {
        let transport = FakeTransport(json: Fixture.ingestReceipt)
        try await pusher(transport).push([Fixture.rollup])
        let request = try #require(transport.requests.first)
        #expect(request.bearerToken == "device-token-for-tests")
        #expect(request.method == .post)
        #expect(request.url.path == "/v1/ingest")
    }

    @Test("no token in the Keychain means unauthorized, and nothing is sent")
    func missingTokenDoesNotSend() async throws {
        let transport = FakeTransport(json: Fixture.ingestReceipt)
        let client = RollupPusher(session: Fixture.session(transport, token: nil),
                                  endpoint: Fixture.origin)
        await #expect(throws: SyncError.unauthorized) {
            try await client.push([Fixture.rollup])
        }
        #expect(transport.requestCount == 0)
    }

    @Test("the body is the { schemaVersion, rollups } envelope the Worker parses")
    func bodyIsTheEnvelope() async throws {
        let transport = FakeTransport(json: Fixture.ingestReceipt)
        try await pusher(transport).push([Fixture.rollup])
        let body = try #require(transport.requests.first?.body)
        let envelope = try SyncCoding.decoder().decode(IngestEnvelope.self, from: body)
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.rollups.count == 1)
        #expect(envelope.rollups.first?.date.rawValue == "2026-11-03")
    }

    @Test("a retried push sends byte-identical bytes — the upsert makes that safe")
    func retrySendsTheSameBytes() async throws {
        let transport = FakeTransport(replies: [
            .response(HTTPResponse(status: 503)),
            .response(.json(Fixture.ingestReceipt))
        ])
        let sleeper = RecordingSleeper()
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .seconds(1), multiplier: 2)
        let report = try await pusher(transport, policy: policy, sleeper: sleeper)
            .push([Fixture.rollup])

        #expect(report.accepted == 1)
        #expect(transport.requestCount == 2)
        #expect(transport.requests[0].body == transport.requests[1].body)
        #expect(sleeper.recorded == [.zero, .seconds(1)])
    }

    @Test("a transport failure is retried, and gives up with the transport error")
    func transportFailureIsRetriedThenThrown() async throws {
        let transport = FakeTransport(replies: [
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet))
        ])
        let policy = RetryPolicy(maxAttempts: 2, initialDelay: .zero, multiplier: 1)
        await #expect(throws: SyncError.self) {
            try await pusher(transport, policy: policy).push([Fixture.rollup])
        }
        #expect(transport.requestCount == 2)
    }

    @Test("contract_violation surfaces every issue and is never retried")
    func contractViolationIsLoudAndFinal() async throws {
        let body = """
            {"schemaVersion":1,"error":"contract_violation",
             "hint":"field names and enums must match docs/EXPORT_SCHEMA.md exactly",
             "issues":[{"path":"rollups.0.training.sessionPlanned","message":"Invalid enum value"},
                       {"path":"rollups.0.wins.total","message":"Expected number"}]}
            """
        let transport = FakeTransport(replies: [.response(.json(status: 400, body))])
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .zero, multiplier: 1)

        let error = await #expect(throws: SyncError.self) {
            try await pusher(transport, policy: policy).push([Fixture.rollup])
        }
        guard case .contractViolation(let issues, let hint) = try #require(error) else {
            Issue.record("expected a contract violation, got \(String(describing: error))")
            return
        }
        #expect(issues.count == 2)
        #expect(issues.first?.path == "rollups.0.training.sessionPlanned")
        #expect(hint?.contains("EXPORT_SCHEMA") == true)
        // A 400 is the client's own fault: sending it again would only repeat it.
        #expect(transport.requestCount == 1)

        let described = SyncError.contractViolation(issues: issues, hint: hint).description
        #expect(described.contains("rollups.0.wins.total"))
        #expect(SyncError.contractViolation(issues: issues, hint: hint).isContractDivergence)
    }

    @Test("a batch is capped at the Worker's 400 and sent oldest first")
    func batchesRespectTheWorkerCap() async throws {
        let rollups = (1...5).map { index in
            Fixture.rollup(date: String(format: "2026-11-%02d", index))
        }
        let transport = FakeTransport(replies: [], fallback: .response(.json(Fixture.ingestReceipt)))
        try await pusher(transport, batchSize: 2).push(rollups.reversed())

        #expect(transport.requestCount == 3)
        let dates = try transport.requests.map { request in
            let body = try #require(request.body)
            return try SyncCoding.decoder().decode(IngestEnvelope.self, from: body)
                .rollups.map(\.date.rawValue)
        }
        #expect(dates == [["2026-11-01", "2026-11-02"],
                          ["2026-11-03", "2026-11-04"],
                          ["2026-11-05"]])
        #expect(RollupPusher.maxBatchSize == 400)
    }

    @Test("a batch size above the Worker's cap is clamped to it")
    func batchSizeIsClamped() async throws {
        let rollups = (1...28).map { index in
            Fixture.rollup(date: String(format: "2026-11-%02d", index % 28 + 1))
        }
        let transport = FakeTransport(replies: [], fallback: .response(.json(Fixture.ingestReceipt)))
        try await pusher(transport, batchSize: 10_000).push(rollups)
        #expect(transport.requestCount == 1)
    }

    @Test("one date twice in a batch collapses to the newer rollup, which the Worker needs")
    func duplicateDatesCollapse() async throws {
        let stale = Fixture.rollup(date: "2026-11-03", updatedAt: "2026-11-03T06:00:00-05:00")
        let fresh = Fixture.rollup(date: "2026-11-03", updatedAt: "2026-11-03T23:05:00-05:00")
        let transport = FakeTransport(json: Fixture.ingestReceipt)
        try await pusher(transport).push([fresh, stale])

        let body = try #require(transport.requests.first?.body)
        let envelope = try SyncCoding.decoder().decode(IngestEnvelope.self, from: body)
        #expect(envelope.rollups.count == 1)
        #expect(envelope.rollups.first?.updatedAt.rawValue == "2026-11-03T23:05:00-05:00")
    }

    @Test("pushing nothing touches the network not at all")
    func emptyPushIsANoOp() async throws {
        let transport = FakeTransport(json: Fixture.ingestReceipt)
        let report = try await pusher(transport).push([])
        #expect(report.accepted == 0)
        #expect(transport.requestCount == 0)
    }

    @Test("a 401 is unauthorized, whatever the body says")
    func unauthorizedIsMapped() async throws {
        let transport = FakeTransport(replies: [
            .response(.json(status: 401, #"{"schemaVersion":1,"error":"unauthorized"}"#))
        ])
        await #expect(throws: SyncError.unauthorized) {
            try await pusher(transport).push([Fixture.rollup])
        }
    }

    @Test("a 413 names the Worker's limit and what was sent")
    func batchTooLargeIsMapped() async throws {
        let body = #"{"schemaVersion":1,"error":"batch_too_large","limit":400,"received":401}"#
        let transport = FakeTransport(replies: [.response(.json(status: 413, body))])
        await #expect(throws: SyncError.batchTooLarge(limit: 400, sent: 401)) {
            try await pusher(transport).push([Fixture.rollup])
        }
    }
}
