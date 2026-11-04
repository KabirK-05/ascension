import AscensionCore
import AscensionEngines
import FeatureTrends
import Foundation
import SyncClient

/// Trends, on real data.
///
/// `FeatureTrends` takes one value and runs `TrendsEngine` over it, so this is the whole
/// seam: refresh the window, then hand over the **entire retained ledger** rather than
/// Today's 17 weeks. The weight trend and the deload detector read months, and a snapshot
/// that silently truncated them would make the engine answer a different question than it
/// was written for.
struct LiveTrendsDataSource: TrendsDataSource {
    private let refresher: DayRefreshService
    private let ledger: RollupStore
    private let flags: FlagsStore

    init(refresher: DayRefreshService, ledger: RollupStore, flags: FlagsStore) {
        self.refresher = refresher
        self.ledger = ledger
        self.flags = flags
    }

    func snapshot() async throws -> TrendsSnapshot {
        let report = await refresher.refresh()
        return TrendsSnapshot(clock: report.clock,
                              goals: report.goals,
                              program: report.program,
                              flags: flags.document,
                              history: await ledger.load().all)
    }
}

/// Accepting the calorie suggestion Trends shows.
///
/// Spec §F6: the engine never changes a target, so accepting is this — and the id is all
/// the tab hands over. The suggestion is therefore *recomputed* from the same snapshot and
/// matched on its id, rather than carried through a side channel: the engine is the only
/// thing that knows what a suggestion means, and asking it twice is how the accepted value
/// is guaranteed to be the proposed one.
///
/// A stale id — the day rolled over, the engine no longer proposes it — throws, which is
/// what makes the card show its failed state instead of silently writing a number nobody
/// saw.
struct StoreSuggestionAcceptor: SuggestionAcceptor {
    enum Failure: Error { case noLongerProposed }

    private let source: LiveTrendsDataSource
    private let store: LocalStore
    private let remote: RemoteDocumentWriter
    private let now: @Sendable () -> Date

    init(source: LiveTrendsDataSource, store: LocalStore, remote: RemoteDocumentWriter,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.store = store
        self.remote = remote
        self.now = now
    }

    func accept(suggestionId: String) async throws {
        let snapshot = try await source.snapshot()
        guard let suggestion = snapshot.report.calorieSuggestion,
              suggestion.id == suggestionId else {
            throw Failure.noLongerProposed
        }

        let updated = try await MainActor.run {
            var document = store.goals
            document.targets.kcal = suggestion.suggestedKcal
            document.version += 1
            document.updatedAt = Timestamp(now(), timeZone: store.timeZone)
            document.updatedBy = .device
            try document.validate()
            try store.replaceGoalSettings(with: document)
            return document
        }
        await remote.write(updated, to: .goalSettings)
    }
}
