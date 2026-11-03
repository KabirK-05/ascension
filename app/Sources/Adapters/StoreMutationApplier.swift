import AscensionCore
import ExportKit
import Foundation
import SwiftData
import SyncClient

/// Applies a drained mutation to the device's own state.
///
/// `SyncClient` declares this protocol because it depends on `AscensionCore` and nothing
/// else; the shell is where SwiftData, the export and the Watch actually live.
///
/// Every method is keyed by `mutationId`. The drain's own ledger already refuses a second
/// delivery, so the ids here are a second line rather than the first: where a row has a
/// natural key — a date, an exercise, a flag — the write is an upsert on that key and
/// cannot double-apply even if the ledger were lost.
struct StoreMutationApplier: LocalStateApplier {
    private let store: LocalStore
    private let flags: FlagsStore
    private let watch: WatchSessionSender
    private let export: ExportRunner
    private let now: @Sendable () -> Date

    init(store: LocalStore,
         flags: FlagsStore,
         watch: WatchSessionSender,
         export: ExportRunner,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.flags = flags
        self.watch = watch
        self.export = export
        self.now = now
    }

    // MARK: - Tier 1 — the documents

    /// The Worker has already bumped the document; this is the local copy catching up so
    /// the app reads the same targets offline.
    ///
    /// `validate()` still has the last word. A patch that breaks the fat floor or leaves
    /// the calorie range is **refused, not clamped** — the contract's rule — and the throw
    /// puts the mutation on the drain's failure counter where a poison pill is visible.
    func applyTargets(_ patch: MutationPayload.TargetsPatch, mutationId: String) async throws {
        try await MainActor.run {
            var document = store.goals
            document.targets = patch.applied(to: document.targets)
            document.version += 1
            document.updatedAt = Timestamp(now(), timeZone: store.timeZone)
            document.updatedBy = .muse
            try document.validate()
            try store.replaceGoalSettings(with: document)
        }
    }

    /// A `program` body carries no `version`/`updatedAt`/`updatedBy` — those are the
    /// Worker's table columns (ASC-12) — so the local copy takes the next version and
    /// records Muse as the author.
    func applyProgram(_ body: MutationPayload.ProgramBody, mutationId: String) async throws {
        try await MainActor.run {
            let document = ProgramDocument(
                version: store.program.version + 1,
                updatedAt: Timestamp(now(), timeZone: store.timeZone),
                updatedBy: .muse,
                name: body.name,
                days: body.days,
                sessions: body.sessions,
                progression: body.progression,
                finisher: body.finisher,
                deload: body.deload)
            try document.validate()
            try store.replaceProgram(with: document)
        }
    }

    func applyStaples(_ staples: [FoodItemDTO], mutationId: String) async throws {
        try await MainActor.run { try store.replaceStaples(with: staples) }
    }

    func applyFlag(_ change: MutationPayload.FlagChange, mutationId: String) async throws {
        flags.apply(key: change.key, value: change.value)
    }

    /// Spec §7 defines no suggestion entity, so there is no local row to mark answered:
    /// the open suggestions live in D1 and the Worker closed this one before queueing the
    /// mutation. Accepting it is therefore a no-op here rather than a silent half-write,
    /// and the ack is still sent so the Worker does not redeliver it.
    func applySuggestion(_ suggestionId: String, mutationId: String) async throws {}

    // MARK: - Tier 2 — the app-owned half

    func applyTopSet(_ payload: MutationPayload.TopSetPayload, mutationId: String) async throws {
        await MainActor.run {
            store.save(topSets: [.init(date: payload.date, exerciseId: payload.exerciseId,
                                       weightKg: payload.weightKg, reps: payload.reps)])
        }
    }

    func applyCheckIn(_ payload: MutationPayload.CheckInPayload,
                      mutationId: String) async throws {
        try await MainActor.run { try store.upsertCheckIn(payload) }
    }

    /// A `schedule_workout` becomes a WorkoutKit plan on the Watch.
    ///
    /// Nothing is written to the store: the schedule *is* the program, and the program
    /// already says what each weekday holds. A kind the program has no template for, or a
    /// device with no reachable Watch, throws — which is what puts it on the failure
    /// counter instead of reporting a success the Watch never saw.
    func scheduleWorkout(_ payload: MutationPayload.ScheduledWorkout,
                         mutationId: String) async throws {
        let program = await store.program
        let names = await store.exerciseNames
        let clock = await DayClock(goals: store.goals)
        try await watch.send(kind: payload.sessionKind, program: program,
                             exerciseNames: names, clock: clock,
                             now: clock.startOfDay(payload.date))
    }

    func triggerExport(mutationId: String) async throws {
        await export.run(trigger: .onDemand)
    }

    /// A `log_meal` belongs in the local diary as well as in Apple Health: the rollup's
    /// macro totals come from logged meals and HealthKit is not read back for them.
    ///
    /// Called only after the HealthKit write succeeded, so a meal that could not reach
    /// Health does not silently become a local-only total.
    func recordLoggedMeal(_ meal: LoggedMeal,
                          payload: MutationPayload.LoggedMealPayload,
                          mutationId: String) async throws {
        try await MainActor.run { try store.insertMeal(payload) }
    }
}
