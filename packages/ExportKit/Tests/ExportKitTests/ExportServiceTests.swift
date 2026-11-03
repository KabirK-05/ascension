import AscensionCore
import Foundation
import Testing

@testable import ExportKit

@Suite("a whole export run")
struct ExportServiceTests {
    private func service(writer: AtomicFileWriter = AtomicFileWriter()) -> ExportService {
        ExportService(destination: ExportDestination(store: InMemoryBookmarkStore()),
                      environment: Fixture.environment,
                      writer: writer)
    }

    @Test("one run writes every file the contract lists")
    func writesEveryFile() throws {
        let folder = try TemporaryFolder()

        let result = try service().write(Fixture.monthSnapshot, to: folder.url,
                                         trigger: .nightly)

        #expect(try folder.contents() == [
            "checkIns.csv", "daily-log.md", "export.json", "meals.csv", "readiness.csv",
            "rollups.csv", "sleep.csv", "summary-latest.md", "topSets.csv",
            "weight.csv", "workouts.csv"
        ])
        #expect(result.trigger == .nightly)
        #expect(result.exportedAt == Fixture.exportedAt)
        #expect(result.recordCounts["rollups"] == 28)
        #expect(result.journalDatesAdded.count == 28)
    }

    @Test("a nightly run and an on-demand run differ only in the trigger")
    func triggersDifferOnlyInName() throws {
        let nightly = try TemporaryFolder()
        let onDemand = try TemporaryFolder()

        let first = try service().write(Fixture.monthSnapshot, to: nightly.url,
                                        trigger: .nightly)
        let second = try service().write(Fixture.monthSnapshot, to: onDemand.url,
                                         trigger: .onDemand)

        #expect(first.trigger == .nightly)
        #expect(second.trigger == .onDemand)
        let nightlyJSON = try nightly.read("export.json")
        let onDemandJSON = try onDemand.read("export.json")
        let nightlyJournal = try nightly.read("daily-log.md")
        let onDemandJournal = try onDemand.read("daily-log.md")
        #expect(nightlyJSON == onDemandJSON)
        #expect(nightlyJournal == onDemandJournal)
    }

    @Test("a second run rewrites the JSON and CSVs but appends no day twice")
    func secondRunAppendsNothing() throws {
        let folder = try TemporaryFolder()
        let service = self.service()

        _ = try service.write(Fixture.monthSnapshot, to: folder.url, trigger: .nightly)
        let journalAfterFirst = try folder.read("daily-log.md")
        let second = try service.write(Fixture.monthSnapshot, to: folder.url,
                                       trigger: .nightly)

        let journalAfterSecond = try folder.read("daily-log.md")
        #expect(second.journalDatesAdded.isEmpty)
        #expect(journalAfterSecond == journalAfterFirst)
        #expect(!second.fileNames.contains("daily-log.md"))
        #expect(second.fileNames.contains("summary-latest.md"))
    }

    @Test("the run resolves the user's folder through the bookmark")
    func runResolvesTheBookmark() throws {
        let folder = try TemporaryFolder()
        let store = InMemoryBookmarkStore()
        let destination = ExportDestination(store: store)
        try destination.adopt(folder.url)
        let service = ExportService(destination: destination,
                                    environment: Fixture.environment)

        let result = try service.runNightly(Fixture.monthSnapshot)

        #expect(result.folder.resolvingSymlinksInPath().path
            == folder.url.resolvingSymlinksInPath().path)
        #expect(try folder.read("export.json") != nil)
    }

    @Test("an on-demand run with no folder chosen reports that, and writes nothing")
    func onDemandWithoutAFolder() throws {
        #expect(throws: ExportError.noDestinationChosen) {
            _ = try self.service().runOnDemand(Fixture.monthSnapshot)
        }
    }

    @Test("the written export.json parses back into the same payload")
    func writtenJSONParsesBack() throws {
        let folder = try TemporaryFolder()
        _ = try service().write(Fixture.monthSnapshot, to: folder.url, trigger: .onDemand)
        let text = try #require(try folder.read("export.json"))

        let payload = try JSONDecoder().decode(ExportPayload.self, from: Data(text.utf8))

        #expect(payload.schemaVersion == 1)
        #expect(payload.rollups.count == 28)
        #expect(payload.documents.goalSettings.targets.proteinG == 150)
        #expect(payload.suggestions.count == 1)
    }

    @Test("every file ends with a newline")
    func filesEndWithNewline() throws {
        let folder = try TemporaryFolder()
        _ = try service().write(Fixture.monthSnapshot, to: folder.url, trigger: .onDemand)

        for name in try folder.contents() {
            let text = try #require(try folder.read(name))
            #expect(text.hasSuffix("\n"), "\(name) does not end with a newline")
        }
    }

    @Test("pork and beef appear only as the rule that excludes them")
    func noExcludedMeats() throws {
        let folder = try TemporaryFolder()
        _ = try service().write(Fixture.monthSnapshot, to: folder.url, trigger: .onDemand)

        for name in try folder.contents() where name != "export.json" {
            let text = try #require(try folder.read(name)).lowercased()
            #expect(!text.contains("pork"), "\(name) mentions pork")
            #expect(!text.contains("beef"), "\(name) mentions beef")
        }
        // In `export.json` each appears exactly once, inside
        // `goalSettings.dietaryRules.excludedMeats` — spec §2 as a stated rule, never
        // as food.
        let json = try #require(try folder.read("export.json")).lowercased()
        #expect(json.components(separatedBy: "pork").count - 1 == 1)
        #expect(json.components(separatedBy: "beef").count - 1 == 1)
    }
}
