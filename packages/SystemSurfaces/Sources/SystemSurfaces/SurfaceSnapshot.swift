import AscensionCore
import Foundation

/// The handful of facts every surface outside the app needs, in one value.
///
/// Widgets, App Intents and the notification scheduler all run where HealthKit and
/// SwiftData are expensive or unreachable — a widget timeline is a different process
/// with no HealthKit authorization of its own — so the app writes this after each
/// refresh and they read it. Deliberately tiny: four numbers and two names, which is
/// everything `docs/SPEC.md` §F8 asks a widget to show and nothing more.
///
/// Every field is what the app last measured, not a prediction. ``updatedAt`` says when,
/// so a reader can tell a quiet morning from a stale one.
public struct SurfaceSnapshot: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var updatedAt: Timestamp

    /// `nil` before the engine has scored the day — no sleep, no HRV, nothing to score.
    public var readinessScore: Int?
    public var verdict: ReadinessVerdict?

    /// The session the program plans today. `nil` on a rest day, which is a fact rather
    /// than a gap.
    public var sessionName: String?
    public var sessionDone: Bool

    public var proteinG: Double
    public var proteinTargetG: Double

    /// Consecutive qualifying days ending today. See ``StreakRule``.
    public var streakDays: Int

    public init(date: CalendarDate,
                updatedAt: Timestamp,
                readinessScore: Int? = nil,
                verdict: ReadinessVerdict? = nil,
                sessionName: String? = nil,
                sessionDone: Bool = false,
                proteinG: Double = 0,
                proteinTargetG: Double = 0,
                streakDays: Int = 0) {
        self.date = date
        self.updatedAt = updatedAt
        self.readinessScore = readinessScore
        self.verdict = verdict
        self.sessionName = sessionName
        self.sessionDone = sessionDone
        self.proteinG = proteinG
        self.proteinTargetG = proteinTargetG
        self.streakDays = streakDays
    }

    /// Protein still owed, floored at zero. The one number the Eat widget exists for.
    public var proteinRemainingG: Double {
        max(proteinTargetG - proteinG, 0)
    }
}

extension SurfaceSnapshot {
    /// The snapshot the app writes for one day of the ledger.
    ///
    /// Reads the rollup rather than recomputing anything: `wins`, the macros and the
    /// readiness score are all already decided on device (`docs/EXPORT_SCHEMA.md` §1), and
    /// a second opinion here is how a widget starts disagreeing with the tab behind it.
    public static func from(today: DayRollup,
                            history: [DayRollup],
                            goals: GoalSettingsDocument,
                            sessionName: String?) -> SurfaceSnapshot {
        SurfaceSnapshot(
            date: today.date,
            updatedAt: today.updatedAt,
            readinessScore: today.readiness?.score,
            verdict: today.readiness?.verdict,
            sessionName: sessionName,
            sessionDone: today.training.sessionDone,
            proteinG: today.nutrition.proteinG ?? 0,
            proteinTargetG: Double(goals.targets.proteinG),
            streakDays: StreakRule.length(history: history, asOf: today.date))
    }
}
