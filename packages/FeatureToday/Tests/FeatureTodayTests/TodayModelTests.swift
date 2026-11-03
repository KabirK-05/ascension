import AscensionCore
import Testing

@testable import FeatureToday

/// The async edge: three states, and a failure that is a state rather than a crash.
@Suite("Today model")
struct TodayModelTests {

    @MainActor
    @Test("a loaded snapshot becomes a presentation")
    func loadSucceeds() async {
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.trainingDay))
        await model.load()
        guard case .ready(let presentation) = model.state else {
            Issue.record("expected ready, got \(model.state)")
            return
        }
        #expect(presentation.session?.name == "Lower A")
    }

    @MainActor
    @Test("a failed load is a state the screen can offer a control for")
    func loadFails() async {
        let model = TodayModel(dataSource: FailingDataSource())
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
    }

    @Test("the default data source is the honest first-launch state, not sample data")
    func defaultDataSourceIsEmpty() async throws {
        let snapshot = try await DefaultTodayDataSource(timezone: Seed.timezone).snapshot()
        #expect(snapshot.today.activity.steps == nil)
        #expect(snapshot.today.sleep.asleepMinutes == nil)
        #expect(snapshot.today.nutrition.proteinG == nil)
        #expect(snapshot.history.isEmpty)
        #expect(snapshot.goals.targets.proteinG == Seed.goalSettings.targets.proteinG)
        #expect(snapshot.program.name == Seed.program.name)
    }

    @Test("the local minute of day is read from the stamp's own offset")
    func minuteOfDay() {
        #expect(TodayFormat.localMinuteOfDay(
            Timestamp.literal("2026-11-03T18:20:00-05:00")) == 18 * 60 + 20)
        #expect(TodayFormat.localMinuteOfDay(
            Timestamp.literal("2026-11-03T00:00:00Z")) == 0)
    }
}

private struct LoadFailure: Error {}

private struct FailingDataSource: TodayDataSource {
    func snapshot() async throws -> TodaySnapshot { throw LoadFailure() }
}
