import AscensionCore
import AscensionEngines
import Foundation
import Testing

@testable import Ascension

/// The ledger on disk. Its job is to survive a relaunch — that is the whole reason history
/// accumulates at all — and to survive a corrupt file without taking the app with it.
@Suite("the rollup store")
struct RollupStoreTests {
    private let today = CalendarDate.literal("2026-11-03")

    private func url() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ascension-tests/\(UUID().uuidString)/rollups.json")
    }

    private func rollup(_ date: CalendarDate, steps: Int) -> DayRollup {
        var day = DayRollup(date: date, timezone: Seed.timezone,
                            updatedAt: Timestamp.literal("2026-11-03T06:00:00-05:00"),
                            wins: Wins(session: false, protein: false,
                                       steps: false, sleep: false))
        day.activity.steps = steps
        return day
    }

    @Test("a merged day is still there after the store is reopened")
    func survivesAReopen() async throws {
        let location = url()
        let first = RollupStore(url: location)
        await first.merge([rollup(today, steps: 9_000)], asOf: today)

        let reopened = RollupStore(url: location)
        let ledger = await reopened.load()

        #expect(ledger.rollup(on: today)?.activity.steps == 9_000)
        #expect(ledger.pending.map(\.date) == [today])
    }

    @Test("a pushed day stays pushed across a reopen")
    func pushedStateSurvives() async throws {
        let location = url()
        let first = RollupStore(url: location)
        let pending = await first.merge([rollup(today, steps: 9_000)], asOf: today)
        await first.markPushed(pending)

        let ledger = await RollupStore(url: location).load()

        #expect(ledger.pending.isEmpty)
        #expect(ledger.rollup(on: today) != nil)
    }

    /// Every day in the ledger is re-derivable from HealthKit and the store, so a bad cache
    /// is not worth refusing to launch over.
    @Test("a corrupt file reads as an empty ledger rather than a failure")
    func corruptFileIsEmpty() async throws {
        let location = url()
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: location)

        let ledger = await RollupStore(url: location).load()

        #expect(ledger.all.isEmpty)
    }
}
