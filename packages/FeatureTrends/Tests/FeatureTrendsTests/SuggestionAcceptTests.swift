import AscensionCore
import AscensionEngines
import Testing

@testable import FeatureTrends

/// The one write this tab can make (spec §F6: never change targets silently).
@MainActor
struct SuggestionAcceptTests {

    /// Records what it was asked to accept, and can be told to fail.
    final class RecordingAcceptor: SuggestionAcceptor, @unchecked Sendable {
        private(set) var accepted: [String] = []
        var failure: (any Error)?

        func accept(suggestionId: String) async throws {
            accepted.append(suggestionId)
            if let failure { throw failure }
        }
    }

    struct Boom: Error {}

    @Test("a stalled fortnight surfaces the engine's suggestion for one tap")
    func stalledWeeksSurfaceASuggestion() async {
        let snapshot = TrendsFixtures.stalled
        #expect(snapshot.report.calorieSuggestion != nil)

        let model = TrendsModel(dataSource: FixtureTrendsDataSource(snapshot))
        await model.load()

        guard case .ready(let presentation) = model.state,
              let panel = presentation.suggestion else {
            Issue.record("expected a suggestion panel")
            return
        }
        #expect(panel.suggestedKcal == CalorieAdjustEngine.slowLossKcal)
        #expect(panel.currentKcal == Seed.goalSettings.targets.kcal)
    }

    @Test("the panel carries the engine's own suggestion id, not one the view made up")
    func panelCarriesTheEngineSuggestionId() async {
        let snapshot = TrendsFixtures.stalled
        guard let suggestion = snapshot.report.calorieSuggestion else {
            Issue.record("fixture no longer produces a suggestion")
            return
        }
        let model = TrendsModel(dataSource: FixtureTrendsDataSource(snapshot))
        await model.load()

        guard case .ready(let presentation) = model.state else {
            Issue.record("expected a ready state")
            return
        }
        #expect(presentation.suggestion?.id == suggestion.id)
        #expect(presentation.suggestion?.reason == suggestion.reason)
    }

    @Test("accepting sends that id to the acceptor exactly once")
    func acceptingSendsTheId() async {
        let snapshot = TrendsFixtures.stalled
        guard let suggestion = snapshot.report.calorieSuggestion else {
            Issue.record("fixture no longer produces a suggestion")
            return
        }
        let acceptor = RecordingAcceptor()
        let model = TrendsModel(dataSource: FixtureTrendsDataSource(snapshot),
                                acceptor: acceptor)
        await model.load()
        await model.accept(suggestionId: suggestion.id)

        #expect(acceptor.accepted == [suggestion.id])
    }

    @Test("a failed accept is a state on the card, never a silent success")
    func failedAcceptIsAState() async {
        let acceptor = RecordingAcceptor()
        acceptor.failure = Boom()
        let model = TrendsModel(dataSource: FixtureTrendsDataSource(TrendsFixtures.stalled),
                                acceptor: acceptor)
        await model.load()
        await model.accept(suggestionId: "calorie-2026-12-05-2000")

        #expect(model.acceptState == .failed)
    }

    @Test("with no acceptor injected, nothing is written and nothing claims it was")
    func noAcceptorWritesNothing() async {
        let model = TrendsModel(dataSource: FixtureTrendsDataSource(TrendsFixtures.stalled))
        await model.load()
        await model.accept(suggestionId: "calorie-2026-12-05-2000")

        #expect(model.acceptState == .idle)
    }

    @Test("a week the rules do not fire on shows no card at all")
    func steadyWeekShowsNoSuggestion() async {
        let model = TrendsModel(dataSource: FixtureTrendsDataSource(TrendsFixtures.cutting))
        await model.load()

        guard case .ready(let presentation) = model.state else {
            Issue.record("expected a ready state")
            return
        }
        #expect(presentation.suggestion == nil)
    }

    @Test("a load failure is a state, not an empty tab pretending to be data")
    func loadFailureIsAState() async {
        struct Failing: TrendsDataSource {
            func snapshot() async throws -> TrendsSnapshot { throw Boom() }
        }
        let model = TrendsModel(dataSource: Failing())
        await model.load()

        guard case .failed = model.state else {
            Issue.record("expected a failed state")
            return
        }
    }
}
