import AscensionCore
import AscensionEngines
import FeatureTrends
import Foundation
import HealthBridge
import SwiftData
import SyncClient
import Testing

@testable import Ascension

/// The second gap ASC-20 left: the shell called `TrendsScreen()`, so the tab ran on
/// `DefaultTrendsDataSource` — the honest first-launch snapshot, which on a device with
/// months of history is simply the wrong answer.
///
/// What is tested here is that the snapshot the tab now receives is the device's own: the
/// ledger's days, the stored documents, and the whole retained history rather than Today's
/// window.
@Suite("the live trends path")
@MainActor
struct LiveTrendsTests {
    private let timeZone = TimeZone(identifier: Seed.timezone) ?? .gmt

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

    private func ledger() -> RollupStore {
        RollupStore(url: FileManager.default.temporaryDirectory
            .appending(path: "trends-rollups.\(UUID().uuidString).json"))
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ascension.tests.trends.\(UUID().uuidString)") ?? .standard
    }

    private func source(store: LocalStore, ledger: RollupStore,
                        flags: FlagsStore) -> LiveTrendsDataSource {
        let bridge = HealthBridgeService(store: FakeHealthStore(), timeZone: timeZone)
        return LiveTrendsDataSource(
            refresher: DayRefreshService(bridge: bridge, store: store, ledger: ledger),
            ledger: ledger,
            flags: flags)
    }

    /// A day far enough back that Today's window would never re-derive it.
    private func oldDay(_ raw: String, weightKg: Double) -> DayRollup {
        var rollup = RollupAssembler.empty(
            date: CalendarDate.literal(raw),
            goals: Seed.goalSettings,
            clock: SyncClient.SystemClock(timeZoneIdentifier: Seed.timezone))
        rollup.body.weightKg = weightKg
        return rollup
    }

    @Test("the snapshot carries the whole retained ledger, not Today's window")
    func historyIsTheWholeLedger() async throws {
        let store = try store()
        let ledger = ledger()
        let old = oldDay("2026-09-15", weightKg: 75.4)
        await ledger.merge([old], asOf: CalendarDate.literal("2026-11-03"))

        let snapshot = try await source(store: store, ledger: ledger,
                                        flags: FlagsStore(defaults: defaults())).snapshot()

        #expect(snapshot.history.contains { $0.date == old.date })
        #expect(snapshot.history.count > 1)
    }

    @Test("the documents are the stored ones, so a Muse edit reaches the tab")
    func documentsComeFromTheStore() async throws {
        let store = try store()
        var goals = store.goals
        goals.targets.kcal = 1_950
        goals.version += 1
        try store.replaceGoalSettings(with: goals)

        let flags = FlagsStore(defaults: defaults())
        flags.setMuseWriteMode(.apply)

        let snapshot = try await source(store: store, ledger: ledger(), flags: flags).snapshot()

        #expect(snapshot.goals.targets.kcal == 1_950)
        #expect(snapshot.flags.museWriteMode == .apply)
        #expect(snapshot.program.name == store.program.name)
    }

    @Test("the clock is the user's timezone, not the device's")
    func clockIsTheUsers() async throws {
        let snapshot = try await source(store: try store(), ledger: ledger(),
                                        flags: FlagsStore(defaults: defaults())).snapshot()
        #expect(snapshot.clock.timezone == Seed.timezone)
    }
}
