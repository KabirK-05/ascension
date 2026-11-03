import AscensionCore
import ExportKit
import FeatureEat
import FeatureToday
import FeatureTrain
import FeatureTrends
import Foundation
import HealthBridge
import SwiftData
import SyncClient

/// The composition root: the one place that builds the real implementations and hands them
/// to the tabs.
///
/// Every feature package was written to receive HealthKit, networking and write-back
/// through protocols so that it builds and tests without a device — CI has no HealthKit at
/// all — and no feature ticket owned the injection. This is it. Hand-written on purpose:
/// spec §8 forbids third-party SDKs, and a container that resolves by type would hide
/// exactly the dependency graph `docs/TECH_STACK.md` §1.2 exists to make visible.
///
/// Read top to bottom and the whole app is here: a store, a HealthKit bridge, a ledger of
/// days, a Watch scheduler, an export, and — only if the device is paired — a sync engine.
@MainActor
final class AppComposition {
    let store: LocalStore
    let bridge: HealthBridgeService

    /// The write-back, built over the same `HKHealthStore` the bridge reads through.
    ///
    /// Taken from the adapter rather than from `bridge.writer`: in Swift 6 an actor's `let`
    /// is actor-isolated, so reaching for it would make every caller of this property
    /// async for no gain. `HealthWriter` is a `Sendable` struct over the same store, so one
    /// built here and the bridge's own are the same thing.
    let writer: HealthWriter
    let ledger: RollupStore
    let refresher: DayRefreshService
    let watch: WatchSessionSender
    let export: ExportRunner
    let identity: DeviceIdentity
    let remote: RemoteBridgeConfiguration

    /// `nil` until the device has both a Worker origin and a device token. Not an error
    /// state: the four tabs are fully usable without it, and nothing retries against a URL
    /// that does not exist or with a token the Worker would reject.
    let sync: SyncEngine?
    let backgroundSync: BackgroundSyncCoordinator?

    /// What the store could not do at launch, for the one place that reports it.
    let startup: StartupReport

    private let flags: FlagsStore

    init(defaults: UserDefaults = .standard) {
        let flags = FlagsStore(defaults: defaults)
        self.flags = flags

        let container = Self.container()
        self.store = LocalStore(container: container.container, flags: flags)
        let seeded = store.installSeed()

        let goals = store.goals
        let heartRate = HeartRateConfiguration(defaults: defaults)
        let timeZone = TimeZone(identifier: goals.timezone) ?? .gmt

        let healthStore = HKHealthStoreAdapter()
        self.bridge = HealthBridgeService(store: healthStore,
                                          timeZone: timeZone,
                                          zones: heartRate.zones)
        self.writer = HealthWriter(store: healthStore)
        let ledger = Self.rollupStore()
        self.ledger = ledger.store
        let refresher = DayRefreshService(bridge: bridge, store: store, ledger: ledger.store)
        self.refresher = refresher
        self.watch = WatchSessionSender(scheduler: Self.scheduler(), zones: heartRate.zones)
        self.export = ExportRunner(store: store, ledger: ledger.store,
                                   destination: ExportDestination(
                                       store: UserDefaultsBookmarkStore(defaults: defaults)))

        let identity = DeviceIdentityProvisioner.provision()
        self.identity = identity
        let remote = RemoteBridgeConfiguration(defaults: defaults, identity: identity)
        self.remote = remote

        let engine = Self.syncEngine(
            remote: remote,
            goals: goals,
            local: StoreMutationApplier(store: store, flags: flags,
                                        watch: watch, export: export),
            health: HealthMutationWriteBack(writer: writer))
        self.sync = engine.engine
        self.backgroundSync = engine.engine.map { built in
            BackgroundSyncCoordinator(
                engine: built,
                rollups: LedgerRollupSource(refresher: refresher),
                clock: SyncClient.SystemClock(timeZoneIdentifier: goals.timezone))
        }

        self.startup = StartupReport(
            storeIsPersistent: container.isPersistent,
            seedInstalled: seeded,
            deviceIdIsPersistent: identity.isPersisted,
            remote: remote.summary,
            watchScheduling: watch.isSupported,
            exportDestinationChosen: export.hasDestination,
            heartRateMaximumKnown: heartRate.maximumBpm != nil,
            syncStateIsPersistent: engine.stateIsPersistent)
    }

    // MARK: - The tabs

    /// Today on live data, with both of its injected actions wired.
    func todayScreen(openEat: @escaping () -> Void) -> TodayScreen {
        let program = store.program
        let names = store.exerciseNames
        let clock = DayClock(goals: store.goals)
        let watch = watch
        return TodayScreen(
            dataSource: LiveTodayDataSource(refresher: refresher),
            sendToWatch: watch.isSupported ? { kind in
                try await watch.send(kind: kind, program: program,
                                     exerciseNames: names, clock: clock)
            } : nil,
            openEat: openEat)
    }

    func trainScreen() -> TrainScreen {
        TrainScreen(environment: TrainEnvironmentFactory.environment(
            bridge: bridge, store: store, watch: watch,
            timeZone: TimeZone(identifier: store.goals.timezone) ?? .gmt))
    }

    /// Eat with the write-back connected, which is what clears the "not in Apple Health"
    /// marker from every diary row.
    func eatScreen() -> EatScreen {
        EatScreen(dependencies: .live(context: store.context,
                                      writeBack: NutritionWriteBackAdapter(writer: writer)))
    }

    /// Trends is still ASC-15's scaffold and takes nothing. There is nothing to inject yet,
    /// and inventing a seam the feature does not declare would be the shell guessing.
    func trendsScreen() -> TrendsScreen {
        TrendsScreen()
    }

    // MARK: - Construction

    /// The store, falling back to memory only if the on-disk one cannot be opened.
    ///
    /// A tab that renders and forgets beats a launch that traps — the same call
    /// `EatDependencies.resolved()` already makes — and ``StartupReport`` says which one
    /// the app got rather than letting the difference pass unnoticed.
    private static func container() -> (container: ModelContainer, isPersistent: Bool) {
        if let onDisk = try? ModelContainer(for: AscensionSchema.schema) {
            return (onDisk, true)
        }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        if let inMemory = try? ModelContainer(for: AscensionSchema.schema,
                                              configurations: configuration) {
            return (inMemory, false)
        }
        // `ModelContainer` has no non-throwing initialiser and the app cannot run without
        // one, so this is the end of the line. Reached only if SwiftData cannot build a
        // container for a schema it has already validated in tests.
        preconditionFailure("SwiftData could not open a container for AscensionSchema")
    }

    private static func rollupStore() -> (store: RollupStore, isPersistent: Bool) {
        if let onDisk = try? RollupStore.applicationSupport() {
            return (onDisk, true)
        }
        let fallback = FileManager.default.temporaryDirectory.appending(path: "rollups.json")
        return (RollupStore(url: fallback), false)
    }

    /// WorkoutKit where it exists, and a scheduler that refuses where it does not.
    ///
    /// `UnavailableSessionScheduler` throws rather than quietly succeeding, which is what
    /// keeps a Send to Watch on a device with no Watch from reporting success.
    private static func scheduler() -> any SessionScheduling {
        let real = WatchSessionScheduler()
        return real.isSupported ? real : UnavailableSessionScheduler()
    }

    private static func syncEngine(
        remote: RemoteBridgeConfiguration,
        goals: GoalSettingsDocument,
        local: any LocalStateApplier,
        health: any HealthWriteBack
    ) -> (engine: SyncEngine?, stateIsPersistent: Bool) {
        guard let endpoint = remote.endpoint, remote.hasDeviceToken else {
            return (nil, false)
        }
        // The applied-id ledger has to survive being killed between a HealthKit write and
        // its ack, or a redelivered `log_meal` totals twice locally. In memory it does not,
        // so that is reported rather than silently accepted.
        let state = try? FileSyncStateStore.applicationSupport()
        let engine = SyncEngine.live(
            origin: endpoint,
            tokens: KeychainDeviceTokenStore(),
            local: local,
            health: health,
            state: state ?? InMemorySyncStateStore(),
            clock: SyncClient.SystemClock(timeZoneIdentifier: goals.timezone))
        return (engine, state != nil)
    }
}
