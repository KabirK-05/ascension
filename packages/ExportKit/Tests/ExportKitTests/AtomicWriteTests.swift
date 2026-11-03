import Foundation
import Testing

@testable import ExportKit

@Suite("atomic writes survive a crash mid-export")
struct AtomicWriteTests {
    @Test("a file is created when nothing was there")
    func createsNewFile() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("export.json")

        try AtomicFileWriter().write(Data("{}".utf8), to: url)

        #expect(try folder.read("export.json") == "{}")
    }

    @Test("a failure between the temp write and the replace leaves the old file intact")
    func failureLeavesPreviousFileIntact() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("export.json")
        try AtomicFileWriter().write(Data("{\"schemaVersion\":1}".utf8), to: url)

        struct Crash: Error {}
        let crashing = AtomicFileWriter(beforeCommit: { _ in throw Crash() })

        #expect(throws: Crash.self) {
            try crashing.write(Data("truncated".utf8), to: url)
        }
        #expect(try folder.read("export.json") == "{\"schemaVersion\":1}")
    }

    @Test("a failed write leaves no temp file behind")
    func failureLeavesNoTempFile() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("export.json")
        try AtomicFileWriter().write(Data("before".utf8), to: url)

        struct Crash: Error {}
        _ = try? AtomicFileWriter(beforeCommit: { _ in throw Crash() })
            .write(Data("after".utf8), to: url)

        #expect(try folder.contents() == ["export.json"])
    }

    @Test("a failure on the very first write leaves no file at all")
    func failureOnFirstWriteLeavesNothing() throws {
        let folder = try TemporaryFolder()
        struct Crash: Error {}

        _ = try? AtomicFileWriter(beforeCommit: { _ in throw Crash() })
            .write(Data("partial".utf8), to: folder.url.appendingPathComponent("new.json"))

        #expect(try folder.contents().isEmpty)
    }

    @Test("a journal half-appended by a crash stays as it was")
    func journalIsNeverHalfAppended() throws {
        let folder = try TemporaryFolder()
        let existing = "# Ascension — daily log\n\n## 2026-11-03 (Tue)\n- Readiness: 70\n"
        try folder.write(existing, to: DailyLogAppender.fileName)

        struct Crash: Error {}
        let service = ExportService(destination: ExportDestination(
            store: InMemoryBookmarkStore()),
            environment: Fixture.environment,
            writer: AtomicFileWriter(beforeCommit: { url in
                guard url.lastPathComponent == DailyLogAppender.fileName else { return }
                throw Crash()
            }))

        #expect(throws: Crash.self) {
            _ = try service.write(Fixture.monthSnapshot, to: folder.url,
                                  trigger: .onDemand)
        }
        #expect(try folder.read(DailyLogAppender.fileName) == existing)
    }

    @Test("reading a file that does not exist is nil, not an error")
    func missingFileReadsAsNil() throws {
        let folder = try TemporaryFolder()

        #expect(try AtomicFileWriter().read(
            folder.url.appendingPathComponent("daily-log.md")) == nil)
    }

    @Test("replacing a file keeps writing the whole new contents, not a prefix")
    func replacementIsWholesale() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("summary-latest.md")
        let writer = AtomicFileWriter()

        try writer.write(Data(String(repeating: "x", count: 4_096).utf8), to: url)
        try writer.write(Data("short".utf8), to: url)

        #expect(try folder.read("summary-latest.md") == "short")
    }
}
