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
import SystemSurfaces

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
    let calendar: CalendarBlockReader
    let changes: ChangeLog
    let surfaces: SurfaceStore
    let activity: SyncActivity
    let settings: RemoteSettings

    /// Recomputed by ``reconfigureRemote()``, because Settings can pair the device without
    /// relaunching it.
    private(set) var remote: RemoteBridgeConfiguration

    /// `nil` until the device has both a Worker origin and a device token. Not an error
    /// state: the four tabs are fully usable without it, and nothing retries against a URL
    /// that does not exist or with a token the Worker would reject.
    private(set) var sync: SyncEngine?
    private(set) var backgroundSync: BackgroundSyncCoordinator?

    /// What the store could not do at launch, for the one place that reports it.
    private(set) var startup: StartupReport

    /// The one composition, for the surfaces the system starts rather than the user:
    /// App Intents are resolved by the system in whatever process it launches, and there
    /// is no initialiser call it passes through. Set once, by ``AppDelegate``.
    static var shared: AppComposition?

    let flags: FlagsStore
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        let calendar = CalendarBlockReader()
        self.calendar = calendar
        let refresher = DayRefreshService(bridge: bridge, store: store, ledger: ledger.store,
                                          calendar: calendar)
        self.refresher = refresher
        self.changes = ChangeLog.applicationSupport()
        self.surfaces = SurfaceStore()
        self.activity = SyncActivity(defaults: defaults)
        self.settings = RemoteSettings(defaults: defaults)
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
            local: StoreMutationApplier(store: store, flags: flags, watch: watch,
                                        export: export, changes: changes),
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

    // MARK: - Pairing

    /// Rebuilds the remote half after Settings changed the origin or the token.
    ///
    /// Pairing happens on a running app, so a `let sync` fixed at launch would mean the
    /// bridge only came alive on the next cold start — and the one thing the acceptance
    /// test (ASC-18) needs first is for the Worker to start receiving days. Everything
    /// below the engine is rebuilt with it: a `SyncEngine` holds its origin and its token
    /// store, so a changed origin is a different engine.
    ///
    /// The background task **handlers** are not touched. `BGTaskScheduler.register` may be
    /// called once per identifier per launch, so ``AppLifecycle`` registers a handler that
    /// asks for ``backgroundSync`` when it fires rather than capturing one at launch.
    func reconfigureRemote() {
        let goals = store.goals
        remote = RemoteBridgeConfiguration(defaults: defaults,
                                           identity: DeviceIdentityProvisioner.provision())
        let engine = Self.syncEngine(
            remote: remote,
            goals: goals,
            local: StoreMutationApplier(store: store, flags: flags, watch: watch,
                                        export: export, changes: changes),
            health: HealthMutationWriteBack(writer: writer))
        sync = engine.engine
        backgroundSync = engine.engine.map { built in
            BackgroundSyncCoordinator(
                engine: built,
                rollups: LedgerRollupSource(refresher: refresher),
                clock: SyncClient.SystemClock(timeZoneIdentifier: goals.timezone))
        }
        startup.remote = remote.summary
        startup.syncStateIsPersistent = engine.stateIsPersistent
    }

    /// Writes a document the device changed back to the Worker, reading the engine at the
    /// moment of the write rather than capturing one — the device may have been paired
    /// since this was built.
    func documentWriter() -> RemoteDocumentWriter {
        RemoteDocumentWriter { [weak self] in
            await MainActor.run { self?.sync }
        }
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
            bridge: bridge, store: store, watch: watch, calendar: calendar,
            timeZone: TimeZone(identifier: store.goals.timezone) ?? .gmt))
    }

    /// Eat with the write-back connected, which is what clears the "not in Apple Health"
    /// marker from every diary row.
    func eatScreen() -> EatScreen {
        EatScreen(dependencies: .live(context: store.context,
                                      writeBack: NutritionWriteBackAdapter(writer: writer)))
    }

    /// Trends on the real ledger, with the one write it can make.
    ///
    /// ASC-15 landed after ASC-20 branched, so the shell was still calling `TrendsScreen()`
    /// and the tab ran on `DefaultTrendsDataSource` — the honest first-launch snapshot,
    /// which on a device with months of history is simply wrong.
    func trendsScreen() -> TrendsScreen {
        let source = trendsSource()
        return TrendsScreen(
            dataSource: source,
            acceptor: StoreSuggestionAcceptor(source: source, store: store,
                                              remote: documentWriter()))
    }

    func trendsSource() -> LiveTrendsDataSource {
        LiveTrendsDataSource(refresher: refresher, ledger: ledger, flags: flags)
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
