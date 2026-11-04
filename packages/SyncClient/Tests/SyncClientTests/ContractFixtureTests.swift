import AscensionCore
import Foundation
import Testing

@testable import SyncClient

/// The bodies this client puts on the wire, frozen as files.
///
/// `edge/src/contract.ts` is the other half of the protocol, and the two are in different
/// languages, so nothing in either compiler can catch a rename. These goldens are what
/// `Scripts/verify-contract-field-names.py` diffs against the zod schemas; the tests here
/// keep them honest, and the enum fixture keeps the closed sets aligned too.
@Suite("Contract fixtures")
struct ContractFixtureTests {
    @Test("the ingest request body is unchanged")
    func ingestRequestGolden() throws {
        let envelope = IngestEnvelope(rollups: [Fixture.rollup])
        try Golden.expect(try Golden.pretty(envelope), matches: "ingest.request.json")
    }

    @Test("the document PUT bodies are unchanged, and carry no envelope keys")
    func documentPutGolden() throws {
        let bodies: [String: JSONValue] = [
            "goalSettings": .object(try RemoteDocument.body(of: Seed.goalSettings)),
            "program": .object(try RemoteDocument.body(of: Seed.program)),
            "flags": .object(try RemoteDocument.body(of: Seed.flags))
        ]
        for (key, body) in bodies {
            let object = try #require(body.objectValue)
            for envelopeKey in RemoteDocument.envelopeKeys {
                #expect(object[envelopeKey] == nil,
                        "\(key) must not carry \(envelopeKey) inside its body")
            }
        }
        try Golden.expect(try Golden.pretty(JSONValue.object(bodies)),
                          matches: "documents.put.json")
    }

    @Test("the mutation ack body is unchanged")
    func ackGolden() throws {
        let ack = MutationAck(ids: [Fixture.Ulid.first, Fixture.Ulid.second],
                              appliedAt: Fixture.clock.timestamp)
        try Golden.expect(try Golden.pretty(ack), matches: "mutations.ack.json")
    }

    @Test("the closed sets this app sends are unchanged")
    func enumGolden() throws {
        let enums: [String: JSONValue] = [
            "sessionKinds": strings(SessionKind.allCases.map(\.rawValue)),
            "verdicts": strings(ReadinessVerdict.allCases.map(\.rawValue)),
            "sorenessLevels": strings(SorenessLevel.allCases.map(\.rawValue)),
            "muscleGroups": strings(MuscleGroup.allCases.map(\.rawValue)),
            "actors": strings(ActorKind.allCases.map(\.rawValue)),
            "documentKeys": strings(SyncDocumentKey.allCases.map(\.rawValue)),
            "mealSlots": strings(MealKind.allCases.map(\.rawValue)),
            "museWriteModes": strings(MuseWriteMode.allCases.map(\.rawValue)),
            "mutationKinds": strings(MutationKind.allCases.map(\.rawValue))
        ]
        try Golden.expect(try Golden.pretty(JSONValue.object(enums)), matches: "enums.json")
    }

    @Test("the schema version is the contract's")
    func schemaVersionIsCurrent() {
        #expect(SyncClientModule.schemaVersion == 1)
        #expect(IngestEnvelope(rollups: []).schemaVersion == 1)
    }

    @Test("the endpoints are the paths edge/src serves")
    func endpointPaths() {
        #expect(Fixture.origin.ingest.path == "/v1/ingest")
        #expect(Fixture.origin.mutations(since: nil).path == "/v1/mutations")
        #expect(Fixture.origin.mutationsAck.path == "/v1/mutations/ack")
        #expect(Fixture.origin.mutations(since: "01JC").query == "since=01JC")
    }

    @Test("every unmeasured field is an explicit null, never an omitted key")
    func unmeasuredFieldsAreExplicitNulls() throws {
        let empty = RollupAssembler.empty(date: CalendarDate.literal("2026-11-04"),
                                          goals: Fixture.goals, clock: Fixture.clock)
        let data = try SyncCoding.encoder().encode(IngestEnvelope(rollups: [empty]))
        let decoded = try SyncCoding.decoder().decode(JSONValue.self, from: data)
        let rollups = try #require(decoded.objectValue?["rollups"]?.arrayValue)
        let rollup = try #require(rollups.first?.objectValue)
        // A zod schema of `.nullable()` without `.optional()` rejects a missing key, which
        // is exactly what `edge/src/contract.ts` declares for every measurement.
        #expect(rollup["checkIn"] == JSONValue.null)
        #expect(rollup["readiness"] == JSONValue.null)
        let nutrition = try #require(rollup["nutrition"]?.objectValue)
        #expect(nutrition.count == 5)
        #expect(nutrition["kcal"] == JSONValue.null)
    }

    private func strings(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}
