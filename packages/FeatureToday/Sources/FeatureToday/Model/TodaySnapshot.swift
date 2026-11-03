import AscensionCore
import AscensionEngines
import Foundation

/// Everything the Today tab renders, as one value.
///
/// The screen is a pure function of this struct, so every card can be driven from a
/// fixture and the rest-day case can be tested without a device, a store or a clock.
public struct TodaySnapshot: Hashable, Sendable {
    /// The instant and timezone the screen is being drawn for.
    public var clock: EngineClock

    public var goals: GoalSettingsDocument
    public var program: ProgramDocument

    /// Today so far. Every measurement is optional and `nil` means *not measured*.
    public var today: DayRollup

    /// The days behind today, in any order; ``today`` is added to them for the grid, so
    /// this does not need to repeat it. Days outside the grid's 17 weeks are ignored,
    /// and days absent from it render as empty cells.
    public var history: [DayRollup]

    /// The 30-day baselines readiness is judged against.
    public var baselines: ReadinessBaselines

    /// When each region was last loaded, for the 48 h rule.
    public var lastTrainedAt: [MuscleRegion: Timestamp]

    /// Yesterday's `loadAu`. `0` is a day that carried no training; `nil` is a day whose
    /// load could not be measured.
    public var yesterdayLoadAu: Double?

    public init(clock: EngineClock,
                goals: GoalSettingsDocument,
                program: ProgramDocument,
                today: DayRollup,
                history: [DayRollup] = [],
                baselines: ReadinessBaselines = ReadinessBaselines(),
                lastTrainedAt: [MuscleRegion: Timestamp] = [:],
                yesterdayLoadAu: Double? = nil) {
        self.clock = clock
        self.goals = goals
        self.program = program
        self.today = today
        self.history = history
        self.baselines = baselines
        self.lastTrainedAt = lastTrainedAt
        self.yesterdayLoadAu = yesterdayLoadAu
    }
}

/// Where a ``TodaySnapshot`` comes from.
///
/// Deliberately one method returning one value type. HealthKit, SwiftData and the sync
/// client all live behind it, so this package depends on none of them: it composes
/// `AscensionCore`, `AscensionEngines` and `DesignSystem` and nothing else, and the app
/// shell is the only place that knows where a step count actually comes from.
public protocol TodayDataSource: Sendable {
    func snapshot() async throws -> TodaySnapshot
}

extension TodaySnapshot {
    /// The number of days the grid can show, today included, so a caller knows how much
    /// history to fetch. Days older than the window are ignored rather than rejected.
    public static let historyDays = 119

    /// What the program prescribes today. `nil` is treated exactly like a rest day.
    public var plannedSession: SessionKind? {
        program.kind(forWeekday: clock.today.isoWeekday)
    }

    /// The session kinds a swap may choose from.
    public var programSessions: Set<SessionKind> {
        Set(program.days.map(\.kind).filter(\.isTrainingDay))
    }

    /// The readiness engine's view of this snapshot.
    public var readinessInput: ReadinessInput {
        ReadinessInput(clock: clock,
                       plannedSession: plannedSession,
                       programSessions: programSessions,
                       sleep: today.sleep,
                       vitals: today.vitals,
                       baselines: baselines,
                       checkIn: today.checkIn,
                       yesterdayLoadAu: yesterdayLoadAu,
                       lastTrainedAt: lastTrainedAt,
                       targets: goals.targets)
    }
}
