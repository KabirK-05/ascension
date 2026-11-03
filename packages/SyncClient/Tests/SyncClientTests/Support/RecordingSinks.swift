import AscensionCore
import Foundation

@testable import SyncClient

/// Counts what reached Apple Health.
///
/// The point of the Tier-2 tests: a mutation delivered twice must produce exactly one
/// write. The recorder keys on `entryId`, which is the mutation's ULID, so a double write
/// is visible as two entries with the same id rather than as a count a test has to
/// interpret.
final class RecordingHealthWriteBack: HealthWriteBack, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var meals: [HealthMealWrite] = []
    private(set) var waters: [WaterWrite] = []
    /// Set to fail the next write, for the blocked-drain test.
    var failure: (any Error)?

    func writeMeal(_ meal: HealthMealWrite) async throws {
        if let failure { throw failure }
        lock.withLock { meals.append(meal) }
    }

    func writeWater(millilitres: Double, at instant: Date, entryId: String) async throws {
        if let failure { throw failure }
        lock.withLock {
            waters.append(WaterWrite(millilitres: millilitres, instant: instant, entryId: entryId))
        }
    }

    func mealWrites(forEntry id: String) -> [HealthMealWrite] {
        lock.withLock { meals.filter { $0.entryId == id } }
    }
}

/// One water write that reached Apple Health.
struct WaterWrite: Hashable, Sendable {
    var millilitres: Double
    var instant: Date
    var entryId: String
}

/// Records every local application, in order, as `kind:mutationId`.
///
/// Order is the assertion that matters for out-of-order delivery, so the log is a flat
/// list of strings rather than per-method counters.
final class RecordingLocalApplier: LocalStateApplier, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var log: [String] = []
    private(set) var targets: [MutationPayload.TargetsPatch] = []
    private(set) var topSets: [MutationPayload.TopSetPayload] = []
    private(set) var meals: [LoggedMeal] = []
    var failure: (any Error)?

    private func record(_ entry: String) throws {
        if let failure { throw failure }
        lock.withLock { log.append(entry) }
    }

    func applyTargets(_ patch: MutationPayload.TargetsPatch, mutationId: String) async throws {
        try record("set_targets:\(mutationId)")
        lock.withLock { targets.append(patch) }
    }

    func applyProgram(_ body: MutationPayload.ProgramBody, mutationId: String) async throws {
        try record("update_program:\(mutationId)")
    }

    func applyStaples(_ staples: [FoodItemDTO], mutationId: String) async throws {
        try record("set_staples:\(mutationId)")
    }

    func applyFlag(_ change: MutationPayload.FlagChange, mutationId: String) async throws {
        try record("set_flag:\(mutationId)")
    }

    func applySuggestion(_ suggestionId: String, mutationId: String) async throws {
        try record("accept_suggestion:\(mutationId)")
    }

    func applyTopSet(_ payload: MutationPayload.TopSetPayload, mutationId: String) async throws {
        try record("log_top_set:\(mutationId)")
        lock.withLock { topSets.append(payload) }
    }

    func applyCheckIn(_ payload: MutationPayload.CheckInPayload, mutationId: String) async throws {
        try record("log_checkin:\(mutationId)")
    }

    func scheduleWorkout(_ payload: MutationPayload.ScheduledWorkout,
                         mutationId: String) async throws {
        try record("schedule_workout:\(mutationId)")
    }

    func triggerExport(mutationId: String) async throws {
        try record("trigger_export:\(mutationId)")
    }

    func recordLoggedMeal(_ meal: LoggedMeal, payload: MutationPayload.LoggedMealPayload,
                          mutationId: String) async throws {
        try record("log_meal:\(mutationId)")
        lock.withLock { meals.append(meal) }
    }
}

/// A failure with a readable description, so an assertion on the blocked reason reads well.
struct TestFailure: Error, CustomStringConvertible {
    var description: String
}
