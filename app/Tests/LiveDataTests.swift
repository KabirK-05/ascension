import AscensionCore
import AscensionEngines
import FeatureToday
import Foundation
import HealthBridge
import SwiftData
import SyncClient
import Testing

@testable import Ascension

/// The ticket's own claim, tested: with HealthKit behind a fake and the store in memory,
/// Today reads a real snapshot assembled from real measurements — not the seeded
/// first-launch state `DefaultTodayDataSource` renders.
@Suite("the live data path")
@MainActor
struct LiveDataTests {
    private let timeZone = TimeZone(identifier: Seed.timezone) ?? .gmt

    /// 3 November 2026, 18:00 in Toronto — a Tuesday, which the seeded program trains.
    private var now: Date {
        Timestamp.literal("2026-11-03T18:00:00-05:00").date ?? Date(timeIntervalSince1970: 0)
    }

    private func store() throws -> LocalStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AscensionSchema.schema,
                                           configurations: configuration)
        let store = LocalStore(container: container)
        #expect(store.installSeed())
        return store
    }

    private func refresher(store: LocalStore, health: FakeHealthStore) -> DayRefreshService {
        let bridge = HealthBridgeService(store: health, timeZone: timeZone)
        let ledger = RollupStore(url: FileManager.default.temporaryDirectory
            .appending(path: "rollups.\(UUID().uuidString).json"))
        return DayRefreshService(bridge: bridge, store: store, ledger: ledger)
    }

    private func steps(_ count: Double, on date: CalendarDate) -> QuantityRecord {
        let clock = DayClock(timeZone: timeZone)
        let start = clock.startOfDay(date).addingTimeInterval(9 * 3_600)
        return QuantityRecord(id: UUID(), metric: .steps, value: count,
                              start: start, end: start.addingTimeInterval(60),
                              sourceName: "iPhone")
    }

    private func sleep(minutes: Int, endingOn date: CalendarDate) -> CategoryRecord {
        let clock = DayClock(timeZone: timeZone)
        let wake = clock.startOfDay(date).addingTimeInterval(7 * 3_600)
        return CategoryRecord(id: UUID(), metric: .sleepAnalysis, value: 1,
                              stage: .asleepCore,
                              start: wake.addingTimeInterval(-Double(minutes) * 60),
                              end: wake, sourceName: "Watch")
    }

    @Test("today's rollup carries the measurements HealthKit reported")
    func measurementsReachTheRollup() async throws {
        let store = try store()
        let health = FakeHealthStore()
        let clock = DayClock(timeZone: timeZone)
        let today = clock.day(of: now)
        health.add([steps(11_500, on: today)])
        health.add([sleep(minutes: 470, endingOn: today)])

        let report = await refresher(store: store, health: health).refresh(now: now)

        #expect(report.today.date == today)
        #expect(report.today.activity.steps == 11_500)
        #expect(report.today.sleep.asleepMinutes == 470)
    }

    /// `wins` is computed once, by `AscensionCore.WinsCalculator`, and never here — a
    /// second implementation is how the grid and the export would come to disagree.
    @Test("the day's wins follow from the targets rather than from the shell")
    func winsComeFromTheCalculator() async throws {
        let store = try store()
        let health = FakeHealthStore()
        let clock = DayClock(timeZone: timeZone)
        let today = clock.day(of: now)
        let targets = store.goals.targets
        health.add([steps(Double(targets.steps) + 500, on: today)])
        health.add([sleep(minutes: targets.sleepMinutes + 10, endingOn: today)])

        let report = await refresher(store: store, health: health).refresh(now: now)

        #expect(report.today.wins.steps)
        #expect(report.today.wins.sleep)
        // Nothing was logged, and a win against an unmeasured value is false, never true.
        #expect(!report.today.wins.protein)
    }

    @Test("readiness is scored for today and lands on the rollup")
    func readinessIsScored() async throws {
        let store = try store()
        let health = FakeHealthStore()
        let clock = DayClock(timeZone: timeZone)
        health.add([sleep(minutes: 450, endingOn: clock.day(of: now))])

        let report = await refresher(store: store, health: health).refresh(now: now)

        let readiness = try #require(report.today.readiness)
        #expect((0...100).contains(readiness.score))
        #expect(!readiness.reasons.isEmpty)
    }

    @Test("Today sees the live snapshot, not the seeded first-launch one")
    func todayDataSourceIsLive() async throws {
        let store = try store()
        let health = FakeHealthStore()
        let clock = DayClock(timeZone: timeZone)
        health.add([steps(8_400, on: clock.day(of: now))])

        let source = LiveTodayDataSource(refresher: refresher(store: store, health: health))
        let snapshot = try await source.snapshot()

        #expect(snapshot.today.activity.steps == 8_400)
        #expect(snapshot.goals == store.goals)
        #expect(snapshot.program == store.program)
    }

    /// The rollups the Worker is sent are the ones the ledger says changed, which is what
    /// `BackgroundSyncCoordinator` asks for on every nightly wake.
    @Test("the rollup source offers the days that changed")
    func rollupSourceOffersPendingDays() async throws {
        let store = try store()
        let health = FakeHealthStore()
        health.add([steps(5_000, on: DayClock(timeZone: timeZone).day(of: now))])

        let source = LedgerRollupSource(refresher: refresher(store: store, health: health))
        let pending = try await source.rollupsToPush()

        #expect(!pending.isEmpty)
        #expect(pending.allSatisfy { $0.timezone == Seed.timezone })
    }
}
