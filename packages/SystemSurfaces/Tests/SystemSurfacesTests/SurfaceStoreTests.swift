import AscensionCore
import Foundation
@testable import SystemSurfaces
import Testing

@Suite("surface store")
struct SurfaceStoreTests {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "surface-\(UUID().uuidString).json")
    }

    private var snapshot: SurfaceSnapshot {
        SurfaceSnapshot(date: CalendarDate.literal("2026-11-03"),
                        updatedAt: Timestamp(Date(), timeZone: .gmt),
                        readinessScore: 74,
                        verdict: .trainAsPlanned,
                        sessionName: "Lower A",
                        sessionDone: false,
                        proteinG: 88,
                        proteinTargetG: 150,
                        streakDays: 6)
    }

    @Test("a written snapshot reads back field for field")
    func roundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SurfaceStore(url: url)

        #expect(store.write(snapshot))
        #expect(store.read() == snapshot)
    }

    @Test("a store with no container reads and writes nothing rather than trapping")
    func absentContainer() {
        let store = SurfaceStore(url: nil)
        #expect(store.write(snapshot) == false)
        #expect(store.read() == nil)
    }

    @Test("an unreadable file is no snapshot, never a half-read one")
    func corruptFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)
        #expect(SurfaceStore(url: url).read() == nil)
    }

    @Test("protein remaining never goes below zero")
    func remainingIsFloored() {
        var over = snapshot
        over.proteinG = 170
        #expect(over.proteinRemainingG == 0)
    }

}
