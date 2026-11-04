import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Cursor durability")
struct CursorDurabilityTests {
    /// A real temp directory: what is under test is that the state survives the process,
    /// and an in-memory fake cannot fail at that.
    private func temporaryStore() throws -> TemporaryStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ascension-sync-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "sync-state.json")
        return TemporaryStore(store: FileSyncStateStore(url: url), url: url)
    }

    private func drain(page: String, store: any SyncStateStore) async throws -> DrainOutcome {
        let transport = FakeTransport(replies: [.response(.json(page))],
                                      fallback: .response(.json(#"{"schemaVersion":1}"#)))
        let local = RecordingLocalApplier()
        let health = RecordingHealthWriteBack()
        let drainer = Fixture.drainer(transport: transport, state: store,
                                      local: local, health: health)
        return DrainOutcome(report: try await drainer.drain(), local: local, health: health)
    }

    @Test("a missing state file reads as a fresh install, not as an error")
    func missingFileIsFresh() throws {
        let kit = try temporaryStore()
        let state = try kit.store.load()
        #expect(state.cursor == nil)
        #expect(state.appliedIds.isEmpty)
        defer { try? FileManager.default.removeItem(at: kit.url.deletingLastPathComponent()) }
    }

    @Test("the cursor and the ledger survive a restart, and nothing re-applies")
    func stateSurvivesARestart() async throws {
        let kit = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: kit.url.deletingLastPathComponent()) }
        let meal = Fixture.logMeal(id: Fixture.Ulid.first)

        let first = try await drain(page: try Fixture.mutationPage([meal]), store: kit.store)
        #expect(first.report.cursor == Fixture.Ulid.first)
        #expect(first.health.meals.count == 1)

        // A second process, pointed at the same file. Nothing in memory carried over.
        let reopened = FileSyncStateStore(url: kit.url)
        #expect(try reopened.load().cursor == Fixture.Ulid.first)
        #expect(try reopened.load().hasApplied(Fixture.Ulid.first))

        let second = try await drain(page: try Fixture.mutationPage([meal]), store: reopened)
        #expect(second.report.applied.isEmpty)
        #expect(second.report.alreadyApplied == [Fixture.Ulid.first])
        #expect(second.health.meals.isEmpty)
    }

    @Test("a mutation applied but not acked is not applied again after a restart")
    func appliedButUnackedDoesNotReapply() async throws {
        let kit = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: kit.url.deletingLastPathComponent()) }
        let meal = Fixture.logMeal(id: Fixture.Ulid.first)

        // The ack fails: the phone lost the network between the Health write and the POST.
        let transport = FakeTransport(replies: [
            .response(.json(try Fixture.mutationPage([meal]))),
            .failure(URLError(.notConnectedToInternet))
        ])
        let health = RecordingHealthWriteBack()
        let drainer = Fixture.drainer(transport: transport, state: kit.store,
                                      local: RecordingLocalApplier(), health: health)
        await #expect(throws: SyncError.self) { try await drainer.drain() }
        #expect(health.meals.count == 1)

        // The ledger was written before the ack was attempted, so the cursor is still
        // where it was and the id is already known.
        let reopened = FileSyncStateStore(url: kit.url)
        #expect(try reopened.load().cursor == nil)
        #expect(try reopened.load().hasApplied(Fixture.Ulid.first))

        let retry = try await drain(page: try Fixture.mutationPage([meal]), store: reopened)
        #expect(retry.health.meals.isEmpty, "the meal must not reach Health a second time")
        #expect(retry.report.alreadyApplied == [Fixture.Ulid.first])
        #expect(retry.report.cursor == Fixture.Ulid.first, "and now the ack lands")
    }

    @Test("the cursor only ever moves forward")
    func cursorIsMonotonic() {
        let state = SyncState(cursor: Fixture.Ulid.second)
        #expect(state.advancingCursor(to: Fixture.Ulid.first).cursor == Fixture.Ulid.second)
        #expect(state.advancingCursor(to: Fixture.Ulid.third).cursor == Fixture.Ulid.third)
    }

    @Test("the ledger is capped, keeping the newest ids")
    func ledgerIsCapped() {
        var state = SyncState()
        let total = SyncState.ledgerLimit + 50
        for index in 0..<total {
            state = state.recordingApplied(String(format: "01JC8X9Y2K3M4N5P6Q7R%05d", index))
        }
        #expect(state.appliedIds.count == SyncState.ledgerLimit)
        #expect(state.hasApplied(String(format: "01JC8X9Y2K3M4N5P6Q7R%05d", total - 1)))
        #expect(!state.hasApplied("01JC8X9Y2K3M4N5P6Q7R00000"))
    }

    @Test("applying clears a recorded failure for that id")
    func applyingClearsTheFailure() {
        let state = SyncState()
            .recordingFailure(Fixture.Ulid.first)
            .recordingApplied(Fixture.Ulid.first)
        #expect(state.failures[Fixture.Ulid.first] == nil)
        #expect(state.hasApplied(Fixture.Ulid.first))
    }

    @Test("the file is replaced, not rewritten, so a kill cannot truncate it")
    func writesAreAtomic() throws {
        let kit = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: kit.url.deletingLastPathComponent()) }
        try kit.store.save(SyncState(cursor: Fixture.Ulid.first,
                                     appliedIds: [Fixture.Ulid.first]))
        try kit.store.save(SyncState(cursor: Fixture.Ulid.second,
                                     appliedIds: [Fixture.Ulid.first, Fixture.Ulid.second]))
        #expect(try kit.store.load().cursor == Fixture.Ulid.second)

        // No temporary file left behind.
        let contents = try FileManager.default
            .contentsOfDirectory(atPath: kit.url.deletingLastPathComponent().path)
        #expect(contents == ["sync-state.json"])
    }
}

/// A state file in a temp directory, and the url it lives at.
struct TemporaryStore {
    var store: FileSyncStateStore
    var url: URL
}

/// One drain's report, plus the sinks it wrote through.
struct DrainOutcome {
    var report: DrainReport
    var local: RecordingLocalApplier
    var health: RecordingHealthWriteBack
}
