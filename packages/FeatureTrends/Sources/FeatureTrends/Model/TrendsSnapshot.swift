import AscensionCore
import AscensionEngines
import Foundation

/// Everything the Trends tab reads, in one value.
///
/// The screen never touches a store, HealthKit or the network: a snapshot arrives, the
/// engine runs over it, and the result is drawn. That is what makes every rule on this
/// tab testable without a simulator and without a clock.
public struct TrendsSnapshot: Sendable {
    public let clock: EngineClock
    public let goals: GoalSettingsDocument
    public let program: ProgramDocument
    public let flags: FlagsDocument

    /// Synced days, in any order. The engine windows them itself.
    public let history: [DayRollup]

    public init(clock: EngineClock,
                goals: GoalSettingsDocument,
                program: ProgramDocument,
                flags: FlagsDocument,
                history: [DayRollup]) {
        self.clock = clock
        self.goals = goals
        self.program = program
        self.flags = flags
        self.history = history
    }

    /// The engine's one pass over the snapshot (spec §F6).
    ///
    /// Everything this tab shows comes from here. Nothing in this package recomputes a
    /// rolling average, a ratio, a threshold or a rate — those live in
    /// `AscensionEngines`, which is unit-tested, and a second implementation in a view is
    /// how the two drift apart.
    public var report: TrendsReport {
        TrendsEngine.report(history: history, goals: goals, program: program, clock: clock)
    }

    /// The same pass, windowed to seven days, for the Sunday review (spec §F7).
    ///
    /// The review reports *this week* — "sessions done vs planned", "avg protein" — while
    /// the tab above it reports the training block, so the two read different windows of
    /// the same engine. `windowDays` is the engine's own parameter: nothing is recomputed
    /// here, the question is just asked over seven days instead of twenty-eight.
    public var weeklyReport: TrendsReport {
        TrendsEngine.report(history: history, goals: goals, program: program, clock: clock,
                            windowDays: WeeklyReview.windowDays)
    }
}

/// Where a ``TrendsSnapshot`` comes from.
///
/// A protocol in this package rather than a dependency on the store or `HealthBridge`:
/// `FeatureTrends` depends on `AscensionCore`, `AscensionEngines` and `DesignSystem`, and
/// the app shell injects the real source.
public protocol TrendsDataSource: Sendable {
    func snapshot() async throws -> TrendsSnapshot
}

/// The snapshot the tab shows before the shell has injected a real source.
///
/// Not sample data: it is the honest first-launch state — the seeded targets and program,
/// and no history at all, because nothing has synced yet. The screen renders that
/// correctly, with em dashes and empty charts rather than invented numbers.
public struct DefaultTrendsDataSource: TrendsDataSource {
    private let timezone: String

    public init(timezone: String = TimeZone.current.identifier) {
        self.timezone = timezone
    }

    public func snapshot() async throws -> TrendsSnapshot {
        let zone = TimeZone(identifier: timezone) ?? .gmt
        let now = Timestamp(Date(), timeZone: zone)
        return TrendsSnapshot(clock: EngineClock(now: now, timezone: timezone),
                              goals: Seed.goalSettings,
                              program: Seed.program,
                              flags: Seed.flags,
                              history: [])
    }
}
