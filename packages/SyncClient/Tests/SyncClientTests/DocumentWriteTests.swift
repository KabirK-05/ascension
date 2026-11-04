import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Document writes — PUT with If-Match")
struct DocumentWriteTests {
    @Test("a write carries If-Match and the body alone, with no envelope keys")
    func bodyExcludesTheEnvelope() async throws {
        let transport = FakeTransport(
            json: Fixture.flagsResponse(version: 3, updatedAt: "2026-11-03T23:05:00-05:00",
                                        updatedBy: "device"))
        let result = try await Fixture.documentClient(transport)
            .write(document: Fixture.flags, to: .flags, ifMatch: 2)

        let request = try #require(transport.requests.first)
        #expect(request.method == .put)
        #expect(request.url.path == "/v1/documents/flags")
        #expect(request.header("If-Match") == "2")

        let body = try #require(request.body)
        let sent = try #require(try SyncCoding.decoder()
            .decode(JSONValue.self, from: body).objectValue)
        // `version`, `updatedAt` and `updatedBy` are columns on the Worker's table; a body
        // that echoed them would fail its strictObject as a contract violation.
        #expect(sent["version"] == nil)
        #expect(sent["updatedAt"] == nil)
        #expect(sent["updatedBy"] == nil)
        #expect(sent["schemaVersion"] == nil)
        #expect(sent["museWriteMode"] == .string("apply"))
        #expect(result.attempts == 1)
        #expect(!result.didMerge)
        #expect(result.document.version == 3)
    }

    @Test("a 409 refetches from the response, merges and retries against the new version")
    func conflictMergesAndRetries() async throws {
        // Muse already turned rawDetailSyncEnabled on, later than this device's edit.
        let remote = Fixture.flagsResponse(version: 5, updatedAt: "2026-11-03T23:30:00-05:00",
                                           museWritesEnabled: true,
                                           rawDetailSyncEnabled: true)
        let accepted = Fixture.flagsResponse(version: 6, updatedAt: "2026-11-03T23:31:00-05:00",
                                             updatedBy: "device", rawDetailSyncEnabled: true)
        let transport = FakeTransport(replies: [
            .response(.json(status: 409, remote)),
            .response(.json(accepted))
        ])

        var mine = Fixture.flags
        mine.museWritesEnabled = false
        let result = try await Fixture.documentClient(transport)
            .write(document: mine, to: .flags, ifMatch: 2,
                   localUpdatedAt: Timestamp.literal("2026-11-03T23:00:00-05:00"))

        #expect(result.attempts == 2)
        #expect(result.didMerge)
        #expect(transport.requestCount == 2)
        // The retry goes against the version the 409 reported, not the stale one.
        #expect(transport.requests[1].header("If-Match") == "5")

        let body = try #require(transport.requests[1].body)
        let merged = try #require(try SyncCoding.decoder()
            .decode(JSONValue.self, from: body).objectValue)
        // Remote was newer, so its value wins the field both sides changed...
        #expect(merged["museWritesEnabled"] == .bool(true))
        // ...and the field only it changed is carried along, not reverted.
        #expect(merged["rawDetailSyncEnabled"] == .bool(true))
        #expect(result.document.version == 6)
    }

    @Test("a local edit newer than the stored document wins its own fields")
    func newerLocalEditWins() async throws {
        let remote = Fixture.flagsResponse(version: 5, updatedAt: "2026-11-03T22:00:00-05:00",
                                           museWritesEnabled: true)
        let accepted = Fixture.flagsResponse(version: 6, updatedAt: "2026-11-03T23:05:00-05:00",
                                             updatedBy: "device", museWritesEnabled: false)
        let transport = FakeTransport(replies: [
            .response(.json(status: 409, remote)),
            .response(.json(accepted))
        ])

        var mine = Fixture.flags
        mine.museWritesEnabled = false
        let result = try await Fixture.documentClient(transport)
            .write(document: mine, to: .flags, ifMatch: 2,
                   localUpdatedAt: Timestamp.literal("2026-11-03T23:00:00-05:00"))

        let body = try #require(transport.requests[1].body)
        let merged = try #require(try SyncCoding.decoder()
            .decode(JSONValue.self, from: body).objectValue)
        #expect(merged["museWritesEnabled"] == .bool(false))
        #expect(result.merges.first?.takenFromLocal == ["museWritesEnabled"])
    }

    @Test("retries are bounded: a device that keeps losing reports rather than loops")
    func retriesAreBounded() async throws {
        let conflict = Fixture.flagsResponse(version: 9, updatedAt: "2026-11-03T23:30:00-05:00")
        let transport = FakeTransport(replies: [], fallback: .response(.json(status: 409,
                                                                             conflict)))
        await #expect(throws: SyncError.conflictUnresolved(key: .flags, attempts: 3)) {
            try await Fixture.documentClient(transport)
                .write(document: Fixture.flags, to: .flags, ifMatch: 2)
        }
        #expect(transport.requestCount == 3)
    }

    @Test("a 409 that answers flat, with an error slug beside the document, still merges")
    func flatConflictBodyMerges() async throws {
        let conflict = """
            {"schemaVersion":1,"error":"version_conflict","version":5,
             "updatedAt":"2026-11-03T23:30:00-05:00","updatedBy":"muse",
             "remoteBridgeEnabled":true,"museWritesEnabled":true,"museWriteMode":"apply",
             "rawDetailSyncEnabled":true,"foundationModelsEnabled":true}
            """
        let accepted = Fixture.flagsResponse(version: 6, updatedAt: "2026-11-03T23:31:00-05:00",
                                             updatedBy: "device", rawDetailSyncEnabled: true)
        let transport = FakeTransport(replies: [
            .response(.json(status: 409, conflict)),
            .response(.json(accepted))
        ])
        let result = try await Fixture.documentClient(transport)
            .write(document: Fixture.flags, to: .flags, ifMatch: 2)

        #expect(result.attempts == 2)
        let body = try #require(transport.requests[1].body)
        let merged = try #require(try SyncCoding.decoder()
            .decode(JSONValue.self, from: body).objectValue)
        // The problem slug is not a document field and must not be written back as one.
        #expect(merged["error"] == nil)
        #expect(merged["rawDetailSyncEnabled"] == .bool(true))
        #expect(merged.count == 5)
    }

    @Test("a status that is not 409 is not merged — it is reported")
    func otherStatusesAreNotMerged() async throws {
        let body = """
            {"schemaVersion":1,"error":"contract_violation",
             "issues":[{"path":"museWriteMode","message":"Invalid enum value"}]}
            """
        let transport = FakeTransport(replies: [.response(.json(status: 400, body))])
        let error = await #expect(throws: SyncError.self) {
            try await Fixture.documentClient(transport)
                .write(document: Fixture.flags, to: .flags, ifMatch: 2)
        }
        #expect(try #require(error).isContractDivergence)
        #expect(transport.requestCount == 1)
    }

    @Test("a fetched document splits envelope from body and decodes as its own type")
    func fetchSplitsEnvelopeFromBody() async throws {
        let transport = FakeTransport(
            json: Fixture.flagsResponse(version: 4, updatedAt: "2026-11-03T18:00:00-05:00"))
        let document = try await Fixture.documentClient(transport).fetch(.flags)

        #expect(document.version == 4)
        #expect(document.updatedBy == .muse)
        #expect(document.body["version"] == nil)
        #expect(document.body["schemaVersion"] == nil)
        #expect(document.body.count == 5)

        let flags = try document.decodeBody(as: FlagsBodyProbe.self)
        #expect(flags.museWriteMode == .apply)
        #expect(flags.remoteBridgeEnabled)
    }

    @Test("a document without a version is a malformed response, not a silent zero")
    func missingVersionIsMalformed() async throws {
        let transport = FakeTransport(json: #"{"schemaVersion":1,"remoteBridgeEnabled":true}"#)
        await #expect(throws: SyncError.self) {
            try await Fixture.documentClient(transport).fetch(.flags)
        }
    }

    @Test("the three document paths are the ones the Worker serves")
    func documentPaths() {
        #expect(Fixture.origin.document(.goalSettings).path == "/v1/documents/goalSettings")
        #expect(Fixture.origin.document(.program).path == "/v1/documents/program")
        #expect(Fixture.origin.document(.flags).path == "/v1/documents/flags")
        #expect(SyncDocumentKey.allCases.map(\.rawValue)
            == ["goalSettings", "program", "flags"])
    }
}

/// The `flags` body alone — `FlagsDocument` carries `version` inline, which a body does not.
struct FlagsBodyProbe: Codable, Hashable, Sendable {
    var remoteBridgeEnabled: Bool
    var museWritesEnabled: Bool
    var museWriteMode: MuseWriteMode
    var rawDetailSyncEnabled: Bool
    var foundationModelsEnabled: Bool
}
