import AscensionCore
import Foundation

/// Applies one mutation, routing it by tier (`docs/MUSE_CAPABILITIES.md`).
///
/// Tier 1 (`set_targets`, `update_program`, `set_staples`, `set_flag`,
/// `accept_suggestion`) was already applied in D1 by the Worker; here it updates local
/// state so the app shows the same thing offline. Tier 2 (`log_*`, `schedule_workout`,
/// `trigger_export`) exists only here, because the APIs it needs are device-only — and the
/// `log_meal` and `log_water` kinds write through ``HealthWriteBack`` so the data lands in
/// Apple Health.
public struct MutationApplier: Sendable {
    private let local: any LocalStateApplier
    private let health: any HealthWriteBack
    private let clock: any SyncClock

    public init(local: any LocalStateApplier, health: any HealthWriteBack, clock: any SyncClock) {
        self.local = local
        self.health = health
        self.clock = clock
    }

    /// Split by tier rather than one switch over eleven kinds: the two halves are
    /// genuinely different — Tier 1 is catching local state up with a write the Worker has
    /// already made, Tier 2 is performing one that only this device can.
    public func apply(_ mutation: Mutation) async throws {
        switch mutation.kind.tier {
        case 1: try await applyTierOne(mutation)
        default: try await applyTierTwo(mutation)
        }
    }

    private func applyTierOne(_ mutation: Mutation) async throws {
        switch mutation.kind {
        case .setTargets:
            try await local.applyTargets(mutation.payload(as: MutationPayload.TargetsPatch.self),
                                         mutationId: mutation.id)
        case .updateProgram:
            try await local.applyProgram(mutation.payload(as: MutationPayload.ProgramBody.self),
                                         mutationId: mutation.id)
        case .setStaples:
            let payload = try mutation.payload(as: MutationPayload.Staples.self)
            try await local.applyStaples(payload.staples, mutationId: mutation.id)
        case .setFlag:
            try await local.applyFlag(mutation.payload(as: MutationPayload.FlagChange.self),
                                      mutationId: mutation.id)
        case .acceptSuggestion:
            let payload = try mutation.payload(as: MutationPayload.AcceptedSuggestion.self)
            try await local.applySuggestion(payload.suggestionId, mutationId: mutation.id)
        default:
            throw SyncError.mutationApplyFailed(id: mutation.id,
                                                reason: "\(mutation.kind.rawValue) is not Tier 1")
        }
    }

    private func applyTierTwo(_ mutation: Mutation) async throws {
        switch mutation.kind {
        case .logMeal:
            try await applyMeal(mutation)
        case .logWater:
            try await applyWater(mutation)
        case .logTopSet:
            try await local.applyTopSet(mutation.payload(as: MutationPayload.TopSetPayload.self),
                                        mutationId: mutation.id)
        case .logCheckIn:
            try await local.applyCheckIn(mutation.payload(as: MutationPayload.CheckInPayload.self),
                                         mutationId: mutation.id)
        case .scheduleWorkout:
            let payload = try mutation.payload(as: MutationPayload.ScheduledWorkout.self)
            try await local.scheduleWorkout(payload, mutationId: mutation.id)
        case .triggerExport:
            try await local.triggerExport(mutationId: mutation.id)
        default:
            throw SyncError.mutationApplyFailed(id: mutation.id,
                                                reason: "\(mutation.kind.rawValue) is not Tier 2")
        }
    }

    /// The HealthKit write comes first and the local record second: a crash between them
    /// leaves the mutation unacked, it is delivered again, and the sync identifier makes
    /// the repeated Health write a replacement rather than a second meal.
    private func applyMeal(_ mutation: Mutation) async throws {
        let payload = try mutation.payload(as: MutationPayload.LoggedMealPayload.self)
        let totals = payload.totals
        let consumedAt = Self.instant(for: payload.date, kind: payload.meal,
                                      timeZone: clock.timeZone)
        try await health.writeMeal(HealthMealWrite(entryId: mutation.id, consumedAt: consumedAt,
                                                   energyKcal: totals.kcal,
                                                   proteinG: totals.proteinG,
                                                   carbsG: totals.carbsG,
                                                   fatG: totals.fatG))
        let meal = LoggedMeal(id: mutation.id, slot: payload.meal,
                              loggedAt: Timestamp(consumedAt, timeZone: clock.timeZone),
                              kcal: totals.kcal, proteinG: totals.proteinG,
                              fatG: totals.fatG, carbsG: totals.carbsG)
        try await local.recordLoggedMeal(meal, payload: payload, mutationId: mutation.id)
    }

    private func applyWater(_ mutation: Mutation) async throws {
        let payload = try mutation.payload(as: MutationPayload.Water.self)
        let instant = Self.instant(for: payload.date, kind: nil, timeZone: clock.timeZone)
        try await health.writeWater(millilitres: payload.ml, at: instant, entryId: mutation.id)
    }

    /// When in the day a logged meal is stamped.
    ///
    /// Muse sends a date, not a time, but HealthKit samples need an instant — and it has to
    /// land inside the right local day or the macros count against the wrong one. The meal
    /// slot gives a conventional hour; a bare date with no slot takes noon, which is inside
    /// every day in every timezone this app sees.
    static func instant(for date: CalendarDate, kind: MealKind?, timeZone: TimeZone) -> Date {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = kind.map(hour(of:)) ?? 12
        components.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static func hour(of kind: MealKind) -> Int {
        switch kind {
        case .breakfast: return 8
        case .lunch: return 13
        case .dinner: return 19
        case .snack: return 16
        }
    }
}
