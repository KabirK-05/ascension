import AscensionCore
import Foundation
import Testing

@testable import ExportKit

@Suite("the destination bookmark resolves and refreshes across launches")
struct DestinationTests {
    @Test("with nothing chosen, an export refuses to guess a folder")
    func noDestinationThrows() {
        let destination = ExportDestination(store: InMemoryBookmarkStore())

        #expect(!destination.hasDestination)
        #expect(throws: ExportError.noDestinationChosen) {
            _ = try destination.resolve()
        }
    }

    @Test("a chosen folder resolves again from the stored bookmark alone")
    func adoptedFolderResolves() throws {
        let folder = try TemporaryFolder()
        let store = InMemoryBookmarkStore()
        let destination = ExportDestination(store: store)

        try destination.adopt(folder.url)
        // A second instance over the same store stands in for the next launch: nothing
        // survives but the bytes in the store.
        let resolved = try ExportDestination(store: store).resolve()
        defer { resolved.release() }

        #expect(store.loadBookmark() != nil)
        #expect(resolved.url.resolvingSymlinksInPath().path
            == folder.url.resolvingSymlinksInPath().path)
    }

    @Test("forgetting the folder clears the bookmark")
    func forgetClearsTheBookmark() throws {
        let folder = try TemporaryFolder()
        let destination = ExportDestination(store: InMemoryBookmarkStore())
        try destination.adopt(folder.url)

        destination.forget()

        #expect(!destination.hasDestination)
    }

    @Test("a bookmark to a folder that is gone fails with a named error")
    func deletedFolderIsNamed() throws {
        let store = InMemoryBookmarkStore()
        let path: URL
        do {
            let folder = try TemporaryFolder()
            path = folder.url
            try ExportDestination(store: store).adopt(folder.url)
        }
        try? FileManager.default.removeItem(at: path)

        #expect(throws: ExportError.self) {
            _ = try ExportDestination(store: store).resolve()
        }
    }

    @Test("a file where a folder should be is refused")
    func aFileIsNotAFolder() throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appendingPathComponent("not-a-folder.json")
        try Data("{}".utf8).write(to: file)
        let store = InMemoryBookmarkStore()
        try ExportDestination(store: store).adopt(file)

        let error = #expect(throws: ExportError.self) {
            _ = try ExportDestination(store: store).resolve()
        }
        // Compared by case rather than by path: a temp directory resolves through the
        // `/private` symlink, so the bookmark reports the canonical path.
        if case .destinationNotADirectory(let path) = try #require(error) {
            #expect(path.hasSuffix("not-a-folder.json"))
        } else {
            Issue.record("expected destinationNotADirectory, got \(String(describing: error))")
        }
    }

    @Test("the nightly run lands at the same local hour across a DST change")
    func nightlyRunIsTimeZoneStable() throws {
        let environment = Fixture.environment
        let before = try #require(Timestamp.literal("2026-10-31T23:00:00-04:00").date)
        let after = try #require(Timestamp.literal("2026-11-02T23:00:00-05:00").date)

        let firstRun = NightlyExport.nextRun(after: before, in: environment)
        let secondRun = NightlyExport.nextRun(after: after, in: environment)

        #expect(environment.calendar.component(.hour, from: firstRun) == NightlyExport.hour)
        #expect(environment.calendar.component(.hour, from: secondRun) == NightlyExport.hour)
        #expect(firstRun > before)
        #expect(secondRun > after)
    }

    @Test("the background identifier is the one Project.swift permits")
    func taskIdentifierMatchesTheProject() {
        #expect(NightlyExport.taskIdentifier == "com.kabirkumar.ascension.nightly-export")
    }
}
