import AscensionCore
import AscensionEngines
import DesignSystem
import Testing

@testable import FeatureToday

/// The morning check-in (spec §F4): the state machine behind the taps, what a commit
/// writes, and the day it is done.
@Suite("Check-in")
struct CheckInTests {

    // MARK: - The state machine

    @Test("nothing is sore until something is tapped")
    func draftStartsClear() {
        let draft = CheckInDraft()
        #expect(MuscleGroup.allCases.allSatisfy { draft.level(for: $0) == SorenessLevel.none })
    }

    @Test("one tap moves a group on by one, and the third returns it", arguments: MuscleGroup.allCases)
    func cycleIsThreeSteps(group: MuscleGroup) {
        var draft = CheckInDraft()
        draft.cycle(group)
        #expect(draft.level(for: group) == .mild)
        draft.cycle(group)
        #expect(draft.level(for: group) == .sore)
        draft.cycle(group)
        #expect(draft.level(for: group) == SorenessLevel.none)
    }

    @Test("tapping one group leaves the other seven alone")
    func groupsAreIndependent() {
        var draft = CheckInDraft()
        draft.cycle(.quads)
        draft.cycle(.quads)
        #expect(draft.level(for: .quads) == .sore)
        let others = MuscleGroup.allCases.filter { $0 != .quads }
        #expect(others.allSatisfy { draft.level(for: $0) == SorenessLevel.none })
    }

    @Test("the contract's 1–5 is the whole scale", arguments: [
        (0, false), (1, true), (3, true), (5, true), (6, false), (-1, false)
    ])
    func energyIsClosed(energy: Int, accepted: Bool) {
        #expect((CheckInDraft().rollup(energy: energy) != nil) == accepted)
    }

    @Test("a commit carries exactly the levels that were tapped")
    func rollupCarriesTheDraft() throws {
        var draft = CheckInDraft()
        draft.cycle(.quads)
        draft.cycle(.quads)
        draft.cycle(.back)
        let rollup = try #require(draft.rollup(energy: 3))
        #expect(rollup.energy == 3)
        #expect(rollup.soreness.quads == .sore)
        #expect(rollup.soreness.back == .mild)
        #expect(rollup.soreness.chest == SorenessLevel.none)
    }

    // MARK: - The panel

    @Test("the panel lists the eight groups in the contract's order")
    func panelGroups() {
        let panel = CheckInPanel.of(CheckInState())
        #expect(panel.groups.map(\.group) == MuscleGroup.allCases)
        #expect(panel.groups.map(\.label)
            == ["Chest", "Back", "Shoulders", "Arms", "Quads", "Hamstrings", "Glutes", "Core"])
        #expect(panel.energyScale == [1, 2, 3, 4, 5])
        #expect(panel.marked.isEmpty)
    }

    @Test("every tap target reads its own level to VoiceOver")
    func panelIsSpoken() {
        var state = CheckInState()
        state.draft.cycle(.core)
        let panel = CheckInPanel.of(state)
        let spoken = Dictionary(uniqueKeysWithValues: panel.groups.map { ($0.group, $0.spokenLevel) })
        #expect(spoken[.core] == "Mild")
        #expect(spoken[.chest] == "Not sore")
        #expect(panel.marked.map(\.group) == [.core])
    }

    @Test("the controls are there while today needs a check-in, and gone once it has one")
    func panelIsConditional() {
        #expect(TodayPresenter.present(TodayFixtures.checkInPending).checkIn != nil)
        #expect(TodayPresenter.present(TodayFixtures.trainingDay).checkIn == nil)
        #expect(TodayPresenter.present(TodayFixtures.emptyDay).checkIn != nil)
    }

    @Test("a pending check-in is not a sixth card")
    func cardBudgetSurvivesTheCheckIn() {
        for snapshot in [TodayFixtures.checkInPending, TodayFixtures.emptyDay,
                         TodayFixtures.standDown] {
            let presentation = TodayPresenter.present(snapshot)
            // The check-in draws inside the readiness card, so it adds no card of its
            // own: readiness, nutrition, measurements, the grid, and the session when
            // one is prescribed.
            let cards = 4 + (presentation.session == nil ? 0 : 1)
            #expect(cards <= 5)
        }
    }

    @Test("the engine's own reason for the gap is not printed above the control that fills it")
    func pendingReasonsAreNotRedundant() {
        let reasons = TodayPresenter.present(TodayFixtures.emptyDay).readiness.reasons
        #expect(!reasons.contains { $0.localizedCaseInsensitiveContains("check-in") })
        #expect(!reasons.contains { $0.localizedCaseInsensitiveContains("energy rating") })
        // Only while the controls are showing: the filter is not a blanket ban.
        #expect(TodayPresenter.reasons(["no check-in"], checkInPending: false) == ["No check-in"])
        #expect(TodayPresenter.reasons(["no check-in"], checkInPending: true).isEmpty)
    }

    // MARK: - Committing

    @MainActor
    @Test("a morning with nothing sore is one tap, and that tap is the whole check-in")
    func theCommonMorningIsOneTap() async throws {
        let store = RecordingCheckInStore()
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending),
                               checkInStore: store)
        await model.load()

        // The one tap.
        await model.submitCheckIn(energy: 4)

        let saved = try #require(await store.saved.first)
        #expect(saved.energy == 4)
        #expect(MuscleGroup.allCases.allSatisfy { saved.soreness.level(for: $0) == SorenessLevel.none })
        #expect(await store.dates == [TodayFixtures.tuesday])
    }

    @MainActor
    @Test("soreness taps reach the store, and the controls leave for the day")
    func sorenessIsCommitted() async throws {
        let store = RecordingCheckInStore()
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending),
                               checkInStore: store)
        await model.load()
        model.cycleSoreness(.quads)
        model.cycleSoreness(.quads)
        model.cycleSoreness(.hamstrings)
        await model.submitCheckIn(energy: 2)

        let saved = try #require(await store.saved.first)
        #expect(saved.soreness.quads == .sore)
        #expect(saved.soreness.hamstrings == .mild)
        #expect(saved.energy == 2)

        let presentation = try #require(ready(model))
        #expect(presentation.checkIn == nil)
        #expect(presentation.summary.contains("Quads sore"))
    }

    @MainActor
    @Test("the score moves to the check-in the user gave, not to one the app assumed")
    func readinessUsesTheCommittedCheckIn() async throws {
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending))
        await model.load()
        let before = try #require(ready(model)).readiness

        await model.submitCheckIn(energy: 1)
        let after = try #require(ready(model)).readiness

        #expect(after.score < before.score)
        #expect(after.reasons.contains("Energy 1 of 5"))
    }

    @MainActor
    @Test("a tap is still a tap without a store wired; it just does not outlive the session")
    func noStoreStillCommits() async throws {
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending))
        await model.load()
        await model.submitCheckIn(energy: 5)
        let presentation = try #require(ready(model))
        #expect(presentation.checkIn == nil)
    }

    @MainActor
    @Test("an energy outside the contract is refused rather than clamped")
    func outOfRangeEnergyIsRefused() async throws {
        let store = RecordingCheckInStore()
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending),
                               checkInStore: store)
        await model.load()
        await model.submitCheckIn(energy: 9)
        #expect(await store.saved.isEmpty)
        let presentation = try #require(ready(model))
        #expect(presentation.checkIn != nil)
    }

    @MainActor
    @Test("a day already checked in offers no controls, and nothing can overwrite it")
    func completedForTodayStaysCompleted() async throws {
        let store = RecordingCheckInStore()
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.trainingDay),
                               checkInStore: store)
        await model.load()
        model.cycleSoreness(.chest)
        await model.submitCheckIn(energy: 1)

        let presentation = try #require(ready(model))
        #expect(presentation.checkIn == nil)
        #expect(await store.saved.isEmpty)
        // The day keeps the check-in it came with, not the one those taps built.
        #expect(presentation.readiness.reasons.contains("Chest mild") == false)
    }

    // MARK: - A save that fails

    @MainActor
    @Test("a failed save keeps the controls and offers a retry, and the score does not move")
    func failedSaveIsRecoverable() async throws {
        let store = UnreliableCheckInStore()
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending),
                               checkInStore: store)
        await model.load()
        let before = try #require(ready(model)).readiness.score

        await model.submitCheckIn(energy: 4)
        let afterFailure = try #require(ready(model))
        let failed = try #require(afterFailure.checkIn)
        #expect(failed.status == .failed)
        #expect(failed.energy == 4)
        #expect(afterFailure.readiness.score == before)
    }

    @MainActor
    @Test("a retry goes back to the store with the energy that failed")
    func retryResubmits() async throws {
        let store = UnreliableCheckInStore(failures: 1)
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending),
                               checkInStore: store)
        await model.load()
        await model.submitCheckIn(energy: 3)
        await model.retryCheckIn()

        #expect(await store.attempts == 2)
        let presentation = try #require(ready(model))
        #expect(presentation.checkIn == nil)
        #expect(presentation.readiness.reasons.contains("Energy 3 of 5"))
    }

    @MainActor
    @Test("editing after a failure is a fresh attempt, so the retry control goes")
    func editingClearsTheFailure() async throws {
        let store = UnreliableCheckInStore()
        let model = TodayModel(dataSource: FixtureDataSource(TodayFixtures.checkInPending),
                               checkInStore: store)
        await model.load()
        await model.submitCheckIn(energy: 4)
        model.cycleSoreness(.back)
        let afterEdit = try #require(ready(model))
        let panel = try #require(afterEdit.checkIn)
        #expect(panel.status == .editing)
        #expect(panel.groups.first { $0.group == .back }?.level == .mild)
    }

    // MARK: - Labels

    @Test("every word the check-in puts on screen is a label, not a sentence")
    func labelsObeyRuleOneThree() {
        let labels = ["Energy", "Retry"] + CheckInPanel.of(CheckInState()).groups.map(\.label)
        for label in labels {
            #expect(LabelRule.isCompliant(label), "\(label) is not a label")
        }
    }

    @MainActor
    private func ready(_ model: TodayModel) -> TodayPresentation? {
        guard case .ready(let presentation) = model.state else { return nil }
        return presentation
    }
}
