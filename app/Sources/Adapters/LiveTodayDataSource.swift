import AscensionCore
import AscensionEngines
import FeatureToday
import Foundation
import SyncClient

/// Today, on real data.
///
/// `TodayDataSource` is one method returning one value type, which is what keeps
/// `FeatureToday` free of HealthKit and SwiftData. Everything expensive has already
/// happened in ``DayRefreshService``; this maps its report onto the snapshot and derives
/// the three readiness inputs from history with `AscensionEngines`, so the numbers Today
/// shows are the same function of the same days as the ones the Worker is sent.
struct LiveTodayDataSource: TodayDataSource {
    private let refresher: DayRefreshService

    init(refresher: DayRefreshService) {
        self.refresher = refresher
    }

    func snapshot() async throws -> TodaySnapshot {
        let report = await refresher.refresh()
        let today = report.clock.today
        let past = report.history.filter { $0.date < today }

        return TodaySnapshot(
            clock: report.clock,
            goals: report.goals,
            program: report.program,
            today: report.today,
            history: past,
            baselines: ReadinessHistory.baselines(past: past, asOf: today),
            lastTrainedAt: ReadinessHistory.lastTrainedAt(history: report.history, asOf: today),
            yesterdayLoadAu: ReadinessHistory.yesterdayLoadAu(past: past, asOf: today))
    }
}

/// The days the Worker has not seen, for `BackgroundSyncCoordinator`.
///
/// A refresh, not a replay of the whole ledger: called on a background task's own time
/// budget, so it answers with the window it has just re-derived plus anything a previous
/// push failed to deliver.
struct LedgerRollupSource: RollupSource {
    private let refresher: DayRefreshService

    init(refresher: DayRefreshService) {
        self.refresher = refresher
    }

    func rollupsToPush() async throws -> [DayRollup] {
        await refresher.refresh().pending
    }
}
