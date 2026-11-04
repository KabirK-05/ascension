import AscensionCore
import Foundation
import Testing

@testable import ExportKit

@Suite("export.json matches the §4 contract")
struct ExportPayloadTests {
    @Test("module is pinned to the current schema version")
    func schemaVersionIsCurrent() {
        #expect(ExportKitModule.schemaVersion == 1)
        #expect(ExportKitModule.schemaVersion == AscensionCoreModule.schemaVersion)
    }

    @Test("a full export of the seeded month matches the golden file")
    func fullExportMatchesGolden() throws {
        let payload = ExportPayload(snapshot: Fixture.monthSnapshot,
                                    exportedAt: Fixture.exportedAt)
        let json = try #require(String(data: try payload.encoded(), encoding: .utf8))
        try Golden.expect(json, matches: "export.expected.json")
    }

    @Test("the top level carries exactly the §4 keys")
    func topLevelKeys() throws {
        let payload = ExportPayload(snapshot: Fixture.monthSnapshot,
                                    exportedAt: Fixture.exportedAt)
        let object = try JSONSerialization.jsonObject(with: try payload.encoded())
        let dictionary = try #require(object as? [String: Any])

        #expect(Set(dictionary.keys) == [
            "schemaVersion", "exportedAt", "recordCounts",
            "rollups", "documents", "meals", "topSets", "checkIns",
            "readiness", "workouts", "sleep", "weight", "suggestions"
        ])
        #expect(dictionary["schemaVersion"] as? Int == 1)
        #expect(dictionary["exportedAt"] as? String == Fixture.exportedAt.rawValue)
    }

    @Test("documents are keyed as the contract names them")
    func documentKeys() throws {
        let payload = ExportPayload(snapshot: Fixture.monthSnapshot,
                                    exportedAt: Fixture.exportedAt)
        let object = try JSONSerialization.jsonObject(with: try payload.encoded())
        let dictionary = try #require(object as? [String: Any])
        let documents = try #require(dictionary["documents"] as? [String: Any])

        #expect(Set(documents.keys) == ["goalSettings", "program", "flags"])
    }

    @Test("recordCounts agrees with the arrays it counts")
    func recordCountsAgree() {
        let snapshot = Fixture.monthSnapshot
        let payload = ExportPayload(snapshot: snapshot, exportedAt: Fixture.exportedAt)

        #expect(payload.recordCounts["rollups"] == 28)
        #expect(payload.recordCounts["meals"] == payload.meals.count)
        #expect(payload.recordCounts["workouts"] == payload.workouts.count)
        #expect(payload.recordCounts["topSets"] == payload.topSets.count)
        #expect(payload.recordCounts["checkIns"] == payload.checkIns.count)
        #expect(payload.recordCounts["readiness"] == payload.readiness.count)
        #expect(payload.recordCounts["sleep"] == payload.sleep.count)
        #expect(payload.recordCounts["weight"] == payload.weight.count)
    }

    @Test("the entity arrays are projections of the rollups, not a second copy")
    func projectionsMatchRollups() {
        let snapshot = Fixture.monthSnapshot
        let fromRollups = snapshot.rollups.flatMap(\.training.workouts).map(\.healthKitId)

        #expect(snapshot.workoutRows.map(\.healthKitId) == fromRollups)
        #expect(snapshot.readinessRows.count
            == snapshot.rollups.count { $0.readiness != nil })
        #expect(snapshot.checkInRows.count == snapshot.rollups.count { $0.checkIn != nil })
    }

    @Test("an unmeasured field is an explicit null, never a missing key")
    func nullsAreExplicit() throws {
        let rollup = DayRollup(date: CalendarDate.literal("2026-11-30"),
                               timezone: Seed.timezone,
                               updatedAt: Fixture.exportedAt,
                               wins: Wins(session: false, protein: false,
                                          steps: false, sleep: false))
        let snapshot = ExportSnapshot(rollups: [rollup], documents: Fixture.documents)
        let data = try ExportPayload(snapshot: snapshot,
                                     exportedAt: Fixture.exportedAt).encoded()
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"kcal\" : null"))
        #expect(text.contains("\"hrvSdnnMs\" : null"))
        #expect(text.contains("\"checkIn\" : null"))
        #expect(text.contains("\"readiness\" : null"))
    }

    @Test("the same snapshot encodes to the same bytes twice")
    func encodingIsStable() throws {
        let snapshot = Fixture.monthSnapshot
        let first = try ExportPayload(snapshot: snapshot,
                                      exportedAt: Fixture.exportedAt).encoded()
        let second = try ExportPayload(snapshot: snapshot,
                                       exportedAt: Fixture.exportedAt).encoded()

        #expect(first == second)
    }

    @Test("a decoded export round-trips to the same bytes")
    func roundTripsThroughDecode() throws {
        let original = try ExportPayload(snapshot: Fixture.monthSnapshot,
                                         exportedAt: Fixture.exportedAt).encoded()
        let decoded = try JSONDecoder().decode(ExportPayload.self, from: original)
        let reencoded = try decoded.encoded()

        #expect(reencoded == original)
    }
}
