import AscensionCore
import AscensionEngines
import FeatureToday
import FeatureTrain
import Foundation
import HealthBridge
import SyncClient

/// Reads HealthKit and the store for a trailing window of days, assembles their rollups and
/// keeps them in the ledger.
///
/// This is where the app stops being a shell and starts being live. Everything downstream —
/// Today's snapshot, the nightly export, the rollups pushed to the Worker — reads the ledger
/// this fills.
///
/// **Why a window and not the whole history.** `HealthStore.statistic(_:in:)` answers for one
/// interval at a time, so a day costs several queries and 119 of them cost several hundred.
/// The window is therefore short and the ledger is cumulative: each refresh re-derives the
/// recent past, where HealthKit data is still arriving and being edited, and leaves older
/// days as they were last assembled. The consequence is stated plainly rather than hidden:
/// **the grid is empty for every day before this ticket shipped**, and fills in from here.
actor DayRefreshService {
    /// Days re-derived on each refresh. Long enough to cover HealthKit's own latency —
    /// sleep and weight arrive and get corrected for a couple of days (`HealthBridge`
    /// re-derives a 3-day window for the same reason) — and short enough to stay cheap.
    static let defaultWindowDays = 7

    struct Report: Sendable {
        var goals: GoalSettingsDocument
        var program: ProgramDocument
        /// The instant the refresh was made for, so every reader of this report agrees on
        /// what "today" and "now" are.
        var clock: EngineClock
        var today: DayRollup
        var history: [DayRollup]
        /// Days the Worker has not been sent. The caller decides whether to push now.
        var pending: [DayRollup]
        var timeZone: TimeZone
    }

    private let bridge: HealthBridgeService
    private let store: LocalStore
    private let ledger: RollupStore
    private let calendar: any TrainingBlockSource

    init(bridge: HealthBridgeService, store: LocalStore, ledger: RollupStore,
         calendar: any TrainingBlockSource = NoTrainingBlocks()) {
        self.bridge = bridge
        self.store = store
        self.ledger = ledger
        self.calendar = calendar
    }

    /// Re-derives the window and returns what the tabs and the sync need.
    ///
    /// Never throws. HealthKit answers a denied read with an empty result that is
    /// indistinguishable from a day with nothing recorded (`ASC-5`), so there is no error
    /// here to surface — an unmeasured day is a measurement of nothing, and every rollup
    /// field is optional precisely so that reads as *not measured* rather than as zero.
    func refresh(windowDays: Int = defaultWindowDays,
                 now: Date = Date()) async -> Report {
        let goals = await store.goals
        let program = await store.program
        let clock = DayClock(goals: goals)
        let syncClock = SyncClient.SystemClock(timeZoneIdentifier: goals.timezone)
        let today = clock.day(of: now)
        let dates = today.trailingWindow(days: max(1, windowDays))

        var snapshots: [String: DayHealthSnapshot] = [:]
        for date in dates {
            snapshots[date.rawValue] = await bridge.snapshot(for: date)
        }

        let trainingDays = await matched(dates: dates, snapshots: snapshots,
                                         program: program, today: today, clock: clock)
        let trendHistory = trendHistory(existing: await ledger.load().all,
                                        dates: dates, snapshots: snapshots,
                                        goals: goals, clock: syncClock)

        var built: [DayRollup] = []
        for day in trainingDays {
            guard let snapshot = snapshots[day.date.rawValue] else { continue }
            let trends = RollupBuilder.trends(history: trendHistory, goals: goals,
                                              asOf: day.date)
            let device = await store.deviceDay(on: day.date,
                                               planned: day.planned,
                                               sessionDone: day.outcome == .completed,
                                               trends: trends,
                                               clock: clock)
            built.append(RollupBuilder.rollup(snapshot: snapshot, device: device,
                                              goals: goals, timeZone: clock.timeZone,
                                              clock: syncClock))
        }

        await ledger.merge(built, asOf: today)

        // Readiness is scored against the merged history, so today's own sleep and vitals
        // are in it and the baselines are the 30 days behind it.
        let merged = await ledger.load()
        var todayRollup = merged.rollup(on: today)
            ?? RollupAssembler.empty(date: today, goals: goals, clock: syncClock)
        todayRollup.readiness = RollupBuilder.readiness(
            history: merged.all,
            clock: clock.engineClock(at: now, goals: goals),
            program: program,
            goals: goals)

        let pending = await ledger.merge([todayRollup], asOf: today)
        let stored = await ledger.load()

        return Report(
            goals: goals,
            program: program,
            clock: clock.engineClock(at: now, goals: goals),
            today: stored.rollup(on: today) ?? todayRollup,
            history: stored.history(endingOn: today, days: TodaySnapshot.historyDays),
            pending: pending,
            timeZone: clock.timeZone)
    }

    /// Whether each day in the window was completed, by `FeatureTrain`'s own matcher.
    ///
    /// Deliberately the matcher and not a rule of the shell's own: ASC-10 warns that an
    /// independent `sessionDone` would make Train and the export disagree about the same
    /// week. The calendar blocks are the same ones Train reads, so the rollup the Worker
    /// is sent and the week the tab draws credit the same workout.
    private func matched(dates: [CalendarDate],
                         snapshots: [String: DayHealthSnapshot],
                         program: ProgramDocument,
                         today: CalendarDate,
                         clock: DayClock) async -> [TrainingDay] {
        let sessions = dates
            .compactMap { snapshots[$0.rawValue] }
            .flatMap(\.workouts)
            .compactMap { CompletedSession($0.summary(timeZone: clock.timeZone)) }
        let blocks = await calendar.blocks(on: dates, program: program,
                                           timeZone: clock.timeZone)
        return SessionMatcher.days(dates, program: program, today: today,
                                   sessions: sessions, blocks: blocks,
                                   timeZone: clock.timeZone)
    }

    /// The weight series the trend engine reads: the ledger's history with the window's
    /// freshly measured days substituted in, so today's weigh-in is part of its own average
    /// and the rate of change still has the weeks behind it to measure against.
    private func trendHistory(existing: [DayRollup],
                              dates: [CalendarDate],
                              snapshots: [String: DayHealthSnapshot],
                              goals: GoalSettingsDocument,
                              clock: some SyncClock) -> [DayRollup] {
        var byDate = Dictionary(existing.map { ($0.date.rawValue, $0) },
                                uniquingKeysWith: { first, _ in first })
        for date in dates {
            guard let snapshot = snapshots[date.rawValue] else { continue }
            let empty = RollupAssembler.empty(date: date, goals: goals, clock: clock)
            byDate[date.rawValue] = snapshot.applied(to: empty, timeZone: clock.timeZone)
        }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
