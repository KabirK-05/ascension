import AscensionCore
import AscensionEngines
import Testing

@testable import FeatureToday

/// The rest-day case, which is the one place the screen must not repeat the engine
/// verbatim. `ReadinessEngine` answers `trainAsPlanned` on a rest day — correctly, since
/// nothing is prescribed to cap or swap — and rendering that literally would tell the
/// user to train on a Sunday.
@Suite("Rest day")
struct RestDayTests {

    @Test("the engine itself still says train as planned on a rest day")
    func engineIsUnchanged() {
        let snapshot = TodayFixtures.restDay
        #expect(snapshot.plannedSession == .rest)
        #expect(ReadinessEngine.assess(snapshot.readinessInput).verdict == .trainAsPlanned)
    }

    @Test("the screen says rest day instead")
    func verdictReadsAsRest() {
        let presentation = TodayPresenter.present(TodayFixtures.restDay)
        #expect(presentation.readiness.verdict == .rest)
        #expect(presentation.readiness.verdict.text == "Rest day")
    }

    @Test("a rest day carries no training instruction anywhere on the screen")
    func noTrainingInstruction() {
        let presentation = TodayPresenter.present(TodayFixtures.restDay)
        #expect(presentation.session == nil)
        #expect(!presentation.summary.contains("Train as planned"))
        #expect(!presentation.summary.lowercased().contains("today,"))
        #expect(presentation.summary.contains("Rest day"))
    }

    @Test("the score is still shown on a rest day")
    func scoreSurvives() {
        let presentation = TodayPresenter.present(TodayFixtures.restDay)
        #expect((0...100).contains(presentation.readiness.score))
        #expect(presentation.readiness.reasons.count == 2)
    }

    @Test("a day the program says nothing about is presented as a rest day too")
    func unplannedDayIsRest() {
        var snapshot = TodayFixtures.trainingDay
        snapshot.program.days = snapshot.program.days.map {
            ProgramDayEntry(weekday: $0.weekday, kind: .rest)
        }
        snapshot.program.sessions = [:]
        let presentation = TodayPresenter.present(snapshot)
        #expect(presentation.readiness.verdict == .rest)
        #expect(presentation.session == nil)
    }

    @Test("every non-rest verdict keeps its own words", arguments: [
        (ReadinessVerdict.trainAsPlanned, "Train as planned"),
        (.capIntensity, "Cap intensity"),
        (.activeRecovery, "Active recovery")
    ])
    func trainingDayVerdicts(verdict: ReadinessVerdict, text: String) {
        let display = VerdictDisplay.of(verdict, plannedSession: .lowerA, suggestedSession: nil)
        #expect(display.text == text)
    }

    @Test("a swap names the session it swaps to")
    func swapNamesItsSession() {
        let display = VerdictDisplay.of(.swapSession, plannedSession: .lowerA,
                                        suggestedSession: .upperB)
        #expect(display.text == "Swap to Upper B")
        #expect(display.prescribedSession(planned: .lowerA) == .upperB)
    }

    @Test("a swap with nothing to swap to stands down rather than naming nothing")
    func swapWithoutSuggestionStandsDown() {
        let display = VerdictDisplay.of(.swapSession, plannedSession: .lowerA,
                                        suggestedSession: nil)
        #expect(display == .activeRecovery)
        #expect(display.prescribedSession(planned: .lowerA) == nil)
    }
}
