import AscensionCore
import ExportKit
import Foundation
import HealthBridge
import OSLog
import SyncClient

#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

/// Everything the app does because it launched, woke, or came back to the foreground.
///
/// Kept apart from ``AppComposition``, which only builds things: this is the part with a
/// clock and a system contract, and it is the part that cannot be tested without a device.
@MainActor
final class AppLifecycle {
    /// Where APNs tokens are kept until something can send them to the Worker.
    ///
    /// **Nothing sends them yet.** `RemoteNotificationRegistrar` deliberately hands the
    /// token to a closure instead of inventing an endpoint, and `edge/` has no route that
    /// takes one (ASC-13). So the token is stored and the silent-push path stays dormant;
    /// the `BGAppRefreshTask` drain and the foreground sync are what make Muse's writes
    /// land, a few minutes later rather than in seconds.
    static let apnsTokenKey = "ascension.apns.deviceToken"

    private let composition: AppComposition
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.kabirkumar.ascension", category: "lifecycle")
    private var didStartObserving = false

    init(composition: AppComposition, defaults: UserDefaults = .standard) {
        self.composition = composition
        self.defaults = defaults
    }

    // MARK: - Launch

    /// Registration has to finish before `didFinishLaunchingWithOptions` returns, so this
    /// runs synchronously and does no work beyond registering.
    ///
    /// Both identifiers are registered whether or not the device is paired: an identifier
    /// in `BGTaskSchedulerPermittedIdentifiers` with no handler is a crash when the system
    /// launches the app for it, and pairing can happen between two launches.
    func registerBackgroundTasks() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NightlyExport.taskIdentifier, using: nil
        ) { [weak self] task in
            // `BGTask` is not `Sendable` and the work is async, so the task has to outlive
            // this closure. The crossing is made explicit rather than hidden behind an
            // `@unchecked Sendable` box: exactly one `Task` ever touches `handle`, once,
            // after its own `await` returns, and the expiration handler only cancels that
            // `Task`, which is `Sendable`. `SyncClient` makes the same crossing for the
            // drain's identifier, for the same reason.
            nonisolated(unsafe) let handle = task
            let work = Task { @MainActor [weak self] in
                let succeeded = await self?.runNightly() ?? false
                self?.scheduleNightly()
                handle.setTaskCompleted(success: succeeded)
            }
            task.expirationHandler = { work.cancel() }
        }
        // The drain's identifier is `SyncClient`'s outright: it registers it and reschedules
        // itself. Nothing registers it when the device is unpaired, which would leave a
        // permitted identifier unhandled — so an unpaired launch registers a handler that
        // reschedules nothing and reports success.
        if let sync = composition.backgroundSync {
            sync.registerMutationDrain()
        } else {
            registerIdleDrain()
        }
        #endif
    }

    /// The nightly job, which is genuinely one job: write the folder, then push the days.
    ///
    /// `NightlyExport.taskIdentifier` and `SyncTaskIdentifier.nightlyPush` are the same
    /// string, and `BGTaskScheduler` allows one handler per identifier, so both halves run
    /// from here. Reported as a success when either half did its work: a nightly wake with
    /// no export folder chosen and nothing to push has not failed, it has nothing to do.
    func runNightly() async -> Bool {
        let exported = await composition.export.run(trigger: .nightly) != nil
        guard let sync = composition.backgroundSync else { return true }
        let pushed = await sync.runNightlyPush()
        return exported || pushed
    }

    /// Asks for the next nightly run at 03:00 local, which `NightlyExport.nextRun` holds
    /// across a daylight-saving change.
    func scheduleNightly() {
        #if canImport(BackgroundTasks) && os(iOS)
        let environment = ExportEnvironment(goalSettings: composition.store.goals)
        let request = BGProcessingTaskRequest(identifier: NightlyExport.taskIdentifier)
        request.earliestBeginDate = NightlyExport.nextRun(after: Date(), in: environment)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        submit(request)
        #endif
    }

    func scheduleMutationDrain() {
        #if canImport(BackgroundTasks) && os(iOS)
        guard let sync = composition.backgroundSync else { return }
        do {
            try sync.scheduleMutationDrain()
        } catch {
            logger.error("could not schedule the mutation drain: \(error, privacy: .public)")
        }
        #endif
    }

    // MARK: - HealthKit

    /// Asks for authorization and starts the observers.
    ///
    /// Asked on first foreground rather than at launch, so the system sheet appears over a
    /// drawn screen instead of a blank one, and asked on every launch because
    /// `requestAuthorization` is a no-op once nothing is outstanding.
    ///
    /// The app is usable before any of it is granted, and that is not a special case:
    /// HealthKit answers a denied read with an empty result that is indistinguishable from
    /// a day with nothing recorded (ASC-5), so an ungranted app is simply an app whose
    /// measurements are all absent — which every rollup field is optional in order to say.
    func startHealth() async {
        do {
            let report = try await composition.bridge.requestAuthorization()
            logger.info("health authorization: \(report.state.rawValue, privacy: .public)")
        } catch {
            logger.info("health unavailable: \(error, privacy: .public)")
            return
        }
        await startObserving()
    }

    /// Observer queries plus background delivery. Registered on every launch — including
    /// one iOS performed in the background — or a wake arrives with nothing listening.
    func startObserving() async {
        guard !didStartObserving else { return }
        didStartObserving = true
        do {
            try await composition.bridge.startObserving { [weak self] metric, delta in
                await self?.handle(metric: metric, delta: delta)
            }
        } catch {
            didStartObserving = false
            logger.info("observers not started: \(error, privacy: .public)")
        }
    }

    /// A delta means HealthKit has something new, so the window is re-derived and the day's
    /// rollup catches up. The delta itself is not applied field by field: the mirrors are a
    /// cache of HealthKit, and re-reading the window is both simpler and idempotent, which
    /// the framework requires — the same change is delivered more than once.
    private func handle(metric: HealthMetric, delta: MirrorDelta) async {
        _ = await composition.refresher.refresh()
    }

    // MARK: - Foreground

    /// What a return to the foreground does: re-derive the window, drain Muse's writes,
    /// push what changed, and ask for the next background slots.
    func onForeground() async {
        await startHealth()
        scheduleNightly()
        scheduleMutationDrain()
        await syncNow()
    }

    /// Drain then push, which is the order that matters: a queued `log_meal` becomes part
    /// of today's rollup, so applying before pushing sends one rollup that already has it.
    func syncNow() async {
        guard let engine = composition.sync else { return }
        let pending = await composition.refresher.refresh().pending
        do {
            _ = try await engine.syncNow(rollups: pending)
            await composition.ledger.markPushed(pending)
        } catch {
            logger.info("sync did not complete: \(error, privacy: .public)")
        }
    }

    // MARK: - Remote notifications

    func registrar() -> RemoteNotificationRegistrar {
        RemoteNotificationRegistrar { [weak self] token in
            await self?.store(apnsToken: token)
        }
    }

    private func store(apnsToken token: String) async {
        defaults.set(token, forKey: Self.apnsTokenKey)
        logger.info("apns token registered, \(token.count, privacy: .public) hex characters")
    }

    /// A silent push asks for a drain. Returns whether anything was applied, which is what
    /// the completion handler reports back to the system.
    ///
    /// Correctness never depends on the push arriving: everything it does, the foreground
    /// sync and the `BGAppRefreshTask` also do. This only makes it sooner.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        // `wantsDrain` is the contract — `{"ascension":{"reason":"mutations"}}` — and it is
        // read here, on the actor the payload arrived on. `SilentPushHandler.handle` would
        // carry the `[AnyHashable: Any]` across isolation, which Swift 6 rejects and is
        // right to: the dictionary comes from Objective-C and is not `Sendable`. Checking
        // first and then calling `drain()`, which takes no payload, keeps it here.
        guard let engine = composition.sync,
              SilentPushHandler.wantsDrain(userInfo: userInfo) else { return false }
        do {
            return try await engine.drain().didApplyAnything
        } catch {
            logger.info("silent push drain failed: \(error, privacy: .public)")
            return false
        }
    }
}

#if canImport(BackgroundTasks) && os(iOS)
extension AppLifecycle {
    private func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulators refuse `BGTaskScheduler.submit`, and so does a device with
            // Background App Refresh switched off. Neither is a failure worth surfacing:
            // the foreground path does the same work.
            logger.info("background task not submitted: \(error, privacy: .public)")
        }
    }

    /// A handler for the drain's identifier on an unpaired device.
    ///
    /// `BGTaskSchedulerPermittedIdentifiers` lists it, and the system terminates an app
    /// that is launched for an identifier it never registered. Nothing is scheduled against
    /// this, so it should never run — but "should never" is not a thing to leave to chance
    /// in a launch handler.
    private func registerIdleDrain() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: SyncTaskIdentifier.mutationDrain, using: nil
        ) { task in
            task.setTaskCompleted(success: true)
        }
    }
}
#endif
