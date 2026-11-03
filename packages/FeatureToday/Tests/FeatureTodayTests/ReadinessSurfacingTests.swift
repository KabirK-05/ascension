import AscensionCore
import AscensionEngines
import Testing

@testable import FeatureToday

/// What the readiness card is allowed to say (spec §F5): the score only as honestly as
/// it was measured, each verdict in full, and a swap that names what to swap to.
@Suite("Readiness surfacing")
struct ReadinessSurfacingTests {

    // MARK: - Each verdict

    @Test("train as planned")
    func trainAsPlanned() {
        let panel = TodayPresenter.present(TodayFixtures.trainingDay).readiness
        #expect(panel.verdict == .trainAsPlanned)
        #expect(panel.verdictText == "Train as planned")
    }

    @Test("a rest day is a rest day, whatever the engine answers for a day with no plan")
    func restDay() {
        let presentation = TodayPresenter.present(TodayFixtures.restDay)
        #expect(presentation.readiness.verdict == .rest)
        #expect(presentation.readiness.verdictText == "Rest day")
        #expect(presentation.session == nil)
    }

    @Test("a stand-down prescribes nothing")
    func activeRecovery() {
        let presentation = TodayPresenter.present(TodayFixtures.standDown)
        #expect(presentation.readiness.verdict == .activeRecovery)
        #expect(presentation.readiness.verdictText == "Active recovery")
        #expect(presentation.session == nil)
    }

    @Test("a swap says what to swap to, by the program's own name for it")
    func swapNamesItsSession() throws {
        let presentation = TodayPresenter.present(TodayFixtures.soreDay)
        let kind = try #require({ () -> SessionKind? in
            guard case .swap(let kind) = presentation.readiness.verdict else { return nil }
            return kind
        }())
        let name = SessionName.of(kind, in: TodayFixtures.soreDay.program)
        #expect(presentation.readiness.verdictText == "Swap to \(name)")
        #expect(presentation.readiness.verdictText != "Swap to")
        // The engine guarantees the suggestion is legal, so the card below must follow it.
        #expect(presentation.session?.kind == kind)
        #expect(kind != TodayFixtures.soreDay.plannedSession)
    }

    @Test("the verdict names a swap the way the program does")
    func swapUsesTheProgramName() {
        let display = VerdictDisplay.swap(.upperA)
        #expect(display.text(in: nil) == "Swap to Upper A")
        #expect(display.text(in: TodayFixtures.trainingDay.program)
            == "Swap to \(SessionName.of(.upperA, in: TodayFixtures.trainingDay.program))")
    }

    @Test("a swap with nothing to swap to falls back to the honest verdict")
    func swapWithoutASessionIsHonest() {
        let display = VerdictDisplay.of(.swapSession,
                                        plannedSession: .lowerA,
                                        suggestedSession: nil)
        #expect(display == .activeRecovery)
    }

    // MARK: - Confidence

    @Test("a score the engine barely measured is written as the estimate it is")
    func lowConfidenceIsMarked() {
        let panel = TodayPresenter.present(TodayFixtures.emptyDay).readiness
        #expect(panel.confidence == .low)
        #expect(panel.scoreText == "~\(panel.score)")
        #expect(panel.spokenScore == "Approximately \(panel.score), low confidence")
        // The number itself is still the engine's, not one invented to fill the gap.
        #expect(panel.score == ReadinessEngine.assess(TodayFixtures.emptyDay.readinessInput).score)
    }

    @Test("a measured score is written plainly")
    func highConfidenceIsPlain() {
        for snapshot in [TodayFixtures.trainingDay, TodayFixtures.soreDay] {
            let panel = TodayPresenter.present(snapshot).readiness
            #expect(panel.confidence != .low)
            #expect(panel.scoreText == panel.score.formatted())
            #expect(panel.spokenScore == panel.score.formatted())
            #expect(!panel.scoreText.contains("~"))
        }
    }

    @Test("the pending check-in costs the fifteen points it is worth, and no more")
    func pendingCheckInNarrowsConfidence() {
        let pending = TodayPresenter.present(TodayFixtures.checkInPending).readiness
        let complete = TodayPresenter.present(TodayFixtures.trainingDay).readiness
        #expect(pending.confidence == .high)
        #expect(complete.confidence == .high)
        let coverage = ReadinessEngine.assess(TodayFixtures.checkInPending.readinessInput).coverage
        #expect(abs(coverage - 0.85) < 0.0001)
    }

    // MARK: - Reasons

    @Test("a verdict standing on a complete check-in shows its facts (spec §F5)")
    func everyVerdictHasItsReasons() {
        for snapshot in [TodayFixtures.trainingDay, TodayFixtures.restDay,
                         TodayFixtures.soreDay, TodayFixtures.standDown] {
            let reasons = TodayPresenter.present(snapshot).readiness.reasons
            #expect(!reasons.isEmpty)
            #expect(reasons.count <= 2)
        }
    }

    @Test("a morning with nothing to report says nothing, and shows the control instead")
    func aQuietPendingMorningIsSilent() {
        // Everything measured on this fixture is unremarkable, so the only facts the
        // engine can rank above them are the two the check-in itself collects. With its
        // controls on the card, that leaves nothing worth a line — which is the point:
        // a reason appears when it is news, not to fill the slot (§2.1).
        let presentation = TodayPresenter.present(TodayFixtures.checkInPending)
        #expect(presentation.checkIn != nil)
        #expect(presentation.readiness.reasons.isEmpty)
    }

    @Test("a fact worth reporting still outranks the missing check-in")
    func anAdverseFactSurvivesThePendingCheckIn() {
        var snapshot = TodayFixtures.checkInPending
        snapshot.today.sleep = SleepRollup(asleepMinutes: 310, consistencySd7Minutes: 22)
        let presentation = TodayPresenter.present(snapshot)
        #expect(presentation.checkIn != nil)
        #expect(presentation.readiness.reasons.contains("Slept 5h10"))
    }

    @Test("a reason is never advice or encouragement", arguments: [
        "should", "try to", "consider", "you ", "let's", "keep it up", "!", "tap to"
    ])
    func reasonsAreFactsOnly(phrase: String) {
        for snapshot in [TodayFixtures.trainingDay, TodayFixtures.restDay,
                         TodayFixtures.soreDay, TodayFixtures.standDown,
                         TodayFixtures.checkInPending, TodayFixtures.emptyDay] {
            for reason in TodayPresenter.present(snapshot).readiness.reasons {
                #expect(!reason.localizedCaseInsensitiveContains(phrase), "\(reason)")
            }
        }
    }
}
