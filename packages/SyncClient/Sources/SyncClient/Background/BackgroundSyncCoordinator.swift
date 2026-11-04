import AscensionCore
import Foundation

#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

/// Where the rollups a background push sends come from.
///
/// The assembly needs HealthKit and the SwiftData store, neither of which this package may
/// touch, so the app shell supplies them behind this. Called on a background task's own
/// time budget, so it should answer with what it already has rather than recompute a year.
public protocol RollupSource: Sendable {
    func rollupsToPush() async throws -> [DayRollup]
}

/// `BGProcessingTask` for the nightly push, `BGAppRefreshTask` for the mutation drain.
///
/// The work itself is ``SyncEngine``'s; this type only owns the scheduling, and it is
/// compiled out everywhere but iOS so the package still tests on macOS. Registration stays
/// with the app shell — ``SyncTaskIdentifier/nightlyPush`` is shared with `ExportKit`'s
/// nightly export, and `BGTaskScheduler` allows one handler per identifier — so what is
/// public here is the two task bodies and the two requests.
public struct BackgroundSyncCoordinator: Sendable {
    private let engine: SyncEngine
    private let rollups: any RollupSource
    private let clock: any SyncClock

    public init(engine: SyncEngine, rollups: any RollupSource, clock: any SyncClock) {
        self.engine = engine
        self.rollups = rollups
        self.clock = clock
    }

    /// The nightly job: drain anything queued, then push the days that changed.
    ///
    /// Returns whether it finished cleanly, which is what `setTaskCompleted(success:)`
    /// wants. A thrown error becomes `false` rather than propagating: an unhandled throw in
    /// a background task leaves the system holding an expired assertion.
    @discardableResult
    public func runNightlyPush() async -> Bool {
        do {
            let pending = try await rollups.rollupsToPush()
            _ = try await engine.syncNow(rollups: pending)
            return true
        } catch {
            return false
        }
    }

    /// The frequent job: drain Muse's write log. No push, because this wake is meant to be
    /// cheap and the nightly job owns the upload.
    @discardableResult
    public func runMutationDrain() async -> Bool {
        do {
            _ = try await engine.drain()
            return true
        } catch {
            return false
        }
    }

    #if canImport(BackgroundTasks) && os(iOS)
    /// Asks for the next nightly run, at the local hour, needing power and the network.
    public func scheduleNightlyPush(scheduler: BGTaskScheduler = .shared) throws {
        let request = BGProcessingTaskRequest(identifier: SyncTaskIdentifier.nightlyPush)
        request.earliestBeginDate = SyncSchedule.nextNightlyRun(after: clock.now,
                                                               in: clock.timeZone)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        try scheduler.submit(request)
    }

    /// Asks for the next drain. Submitted again at the end of every drain, since
    /// `BGTaskScheduler` keeps one pending request per identifier.
    public func scheduleMutationDrain(scheduler: BGTaskScheduler = .shared) throws {
        let request = BGAppRefreshTaskRequest(identifier: SyncTaskIdentifier.mutationDrain)
        request.earliestBeginDate = clock.now.addingTimeInterval(SyncSchedule.drainRefreshInterval)
        try scheduler.submit(request)
    }

    /// Registers the drain's `BGAppRefreshTask`, reschedules itself, and reports the
    /// outcome. The nightly identifier is deliberately not registered here: `ExportKit`
    /// shares it, so the app shell registers it once and calls ``runNightlyPush()`` from
    /// inside that one handler.
    @discardableResult
    public func registerMutationDrain(scheduler: BGTaskScheduler = .shared) -> Bool {
        scheduler.register(forTaskWithIdentifier: SyncTaskIdentifier.mutationDrain,
                           using: nil) { task in
            // `BGTask` is not `Sendable`, and the drain is async, so the task has to
            // outlive this closure: there is no spelling of "await, then report the
            // outcome" that complete concurrency checking accepts, and hopping to the
            // main actor does not help — the launch handler itself is task-isolated, so
            // the task cannot leave it by any route.
            //
            // The crossing is therefore made explicit here rather than hidden behind an
            // `@unchecked Sendable` wrapper. It is sound because exactly one `Task` ever
            // touches `handle`, once, after its own `await` has returned; the expiration
            // handler only cancels that `Task`, which is `Sendable`. The reschedule goes
            // through `.shared` because `BGTaskScheduler` has no public initialiser —
            // `scheduler` is always that same object, so there is nothing to forward.
            nonisolated(unsafe) let handle = task
            let work = Task {
                let succeeded = await self.runMutationDrain()
                try? self.scheduleMutationDrain()
                handle.setTaskCompleted(success: succeeded)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
    #endif
}
