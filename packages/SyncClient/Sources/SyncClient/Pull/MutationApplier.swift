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

    /// How many times a HealthKit write is attempted before the drain gives up on it and
    /// records a refusal the user can see.
    ///
    /// Three, and the number matters in both directions. Fewer than one retry and a scope
    /// granted a moment after Muse logged the meal would never get a second chance. More,
    /// and a permanently refused scope — or a value HealthKit will never take — sits at the
    /// head of the queue blocking every later mutation, because ``MutationDrainer`` stops
    /// the drain at a failure rather than skipping past it. Three drains is enough to cover
    /// a scope the user grants while the app is open, and short enough that a refusal the
    /// user has to act on reaches them while they still remember asking for the meal.
    public static let healthWriteAttemptLimit = 3

    /// Split by tier rather than one switch over eleven kinds: the two halves are
    /// genuinely different — Tier 1 is catching local state up with a write the Worker has
    /// already made, Tier 2 is performing one that only this device can.
    ///
    /// `previousFailures` is the drain's own count for this mutation id, and it is here
    /// because only the two `log_*` kinds that reach Apple Health can fail in a way worth
    /// retrying rather than reporting. The policy lives in this type; the ledger lives in
    /// ``SyncState``; neither needs to know how the other works.
    public func apply(_ mutation: Mutation, previousFailures: Int = 0) async throws {
        switch mutation.kind.tier {
        case 1: try await applyTierOne(mutation)
        default: try await applyTierTwo(mutation, attempt: previousFailures + 1)
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

    private func applyTierTwo(_ mutation: Mutation, attempt: Int) async throws {
        switch mutation.kind {
        case .logMeal:
            try await applyMeal(mutation, attempt: attempt)
        case .logWater:
            try await applyWater(mutation, attempt: attempt)
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
    ///
    /// **The local record is conditional on the write, which is the whole of ASC-27.** The
    /// write reports a refused scope in its outcome instead of throwing, so for a while
    /// this method took "it returned" for "it worked", wrote the diary row anyway, and let
    /// the drain ack a meal Apple Health had never seen. HealthKit is the source of truth
    /// (`docs/SPEC.md` §3); a diary row Health cannot corroborate is divergence, not a meal.
    private func applyMeal(_ mutation: Mutation, attempt: Int) async throws {
        let payload = try mutation.payload(as: MutationPayload.LoggedMealPayload.self)
        let totals = payload.totals
        let consumedAt = Self.instant(for: payload.date, kind: payload.meal,
                                      timeZone: clock.timeZone)
        let outcome = try await health.writeMeal(
            HealthMealWrite(entryId: mutation.id, consumedAt: consumedAt,
                            energyKcal: totals.kcal, proteinG: totals.proteinG,
                            carbsG: totals.carbsG, fatG: totals.fatG))
        guard outcome.reachedEverything else {
            return try await giveUpOrRetry(mutation, outcome: outcome, attempt: attempt,
                                           subject: .meal(payload))
        }
        let meal = LoggedMeal(id: mutation.id, slot: payload.meal,
                              loggedAt: Timestamp(consumedAt, timeZone: clock.timeZone),
                              kcal: totals.kcal, proteinG: totals.proteinG,
                              fatG: totals.fatG, carbsG: totals.carbsG)
        try await local.recordLoggedMeal(meal, payload: payload, mutationId: mutation.id)
    }

    /// Water has no local row to get wrong — Apple Health is the only place it lands — so a
    /// refused scope means the mutation achieved nothing at all, and acking it would be the
    /// same lie in a smaller package.
    private func applyWater(_ mutation: Mutation, attempt: Int) async throws {
        let payload = try mutation.payload(as: MutationPayload.Water.self)
        let instant = Self.instant(for: payload.date, kind: nil, timeZone: clock.timeZone)
        let outcome = try await health.writeWater(millilitres: payload.ml, at: instant,
                                                  entryId: mutation.id)
        if !outcome.reachedEverything {
            try await giveUpOrRetry(mutation, outcome: outcome, attempt: attempt,
                                    subject: .water(millilitres: payload.ml))
        }
    }

    /// What to do about a write Apple Health would not take.
    ///
    /// Throwing leaves the mutation unacked, so the Worker delivers it again and the next
    /// drain tries once more — which is the right answer while there is any chance the
    /// refusal was temporary, and the only thing that makes granting the scope afterwards
    /// actually recover the meal.
    ///
    /// It cannot be the answer forever. A scope the user has refused outright does not heal
    /// on its own, and ``MutationDrainer`` holds every later mutation behind a failing one,
    /// so an unbounded retry would trade one lost meal for Muse's whole write channel. At
    /// the limit the drain stops retrying, acks, and records a refusal the user can see in
    /// Settings → Changes — which is also the only thing that can prompt the one action
    /// that fixes this, since the fix is in the user's hands and not the app's.
    private func giveUpOrRetry(_ mutation: Mutation, outcome: HealthWriteOutcome,
                               attempt: Int,
                               subject: RefusedHealthWrite.Subject) async throws {
        let refused = outcome.refusedMetrics.sorted()
        guard attempt >= Self.healthWriteAttemptLimit else {
            throw SyncError.mutationApplyFailed(
                id: mutation.id,
                reason: "Apple Health refused \(refused.joined(separator: ", ")) "
                    + "— attempt \(attempt) of \(Self.healthWriteAttemptLimit), "
                    + "the mutation stays queued")
        }
        try await local.recordRefusedHealthWrite(
            RefusedHealthWrite(subject: subject, refusedMetrics: refused, attempts: attempt),
            mutationId: mutation.id)
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
