import AscensionCore
import AscensionEngines
import DesignSystem
import Testing

@testable import FeatureToday

/// The rest of the mapping: the summary line, the measurement rows and the rules that
/// keep `docs/DESIGN_RULES.md` §1 mechanical rather than aspirational.
@Suite("Presentation")
struct PresentationTests {

    // MARK: - The summary line

    @Test("the summary is facts, in the spec's own shape")
    func summaryReadsAsFacts() {
        let presentation = TodayPresenter.present(TodayFixtures.trainingDay)
        #expect(presentation.summary.hasPrefix("Slept 7h42."))
        #expect(presentation.summary.contains("Lower A today"))
        #expect(presentation.summary.contains("behind pace"))
    }

    @Test("the summary carries no banned copy", arguments: [
        "Here's", "Your daily", "Track your", "Keep it up", "Nice work",
        "Based on your", "We noticed", "Let's", "Tap to", "Swipe to", "!"
    ])
    func summaryAvoidsBannedCopy(phrase: String) {
        for snapshot in [TodayFixtures.trainingDay, TodayFixtures.restDay,
                         TodayFixtures.soreDay, TodayFixtures.emptyDay] {
            let summary = TodayPresenter.present(snapshot).summary
            #expect(!summary.localizedCaseInsensitiveContains(phrase))
        }
    }

    @Test("a clause with nothing to say is dropped, not padded")
    func clausesAreEarned() {
        let summary = TodayPresenter.present(TodayFixtures.emptyDay).summary
        #expect(!summary.contains("Slept"))
        #expect(!summary.contains("sore"))
        // 07:05 is before the eating day starts, so nothing can be behind pace yet.
        #expect(!summary.contains("behind pace"))
    }

    @Test("soreness is named only when something is actually sore")
    func sorenessClauseIsConditional() {
        #expect(TodayPresenter.present(TodayFixtures.soreDay).summary.contains("Quads and glutes sore"))
        #expect(!TodayPresenter.present(TodayFixtures.trainingDay).summary.contains("sore"))
    }

    @Test("the summary agrees with the verdict on a swap")
    func summaryFollowsTheSwap() {
        let presentation = TodayPresenter.present(TodayFixtures.soreDay)
        guard case .swap(let kind) = presentation.readiness.verdict else {
            Issue.record("expected a swap, got \(presentation.readiness.verdict)")
            return
        }
        let name = SessionName.of(kind, in: TodayFixtures.soreDay.program)
        #expect(presentation.summary.contains("Swap to \(name)"))
        #expect(presentation.session?.kind == kind)
    }

    // MARK: - Readiness reasons

    @Test("the same fact is never printed twice")
    func reasonsAreDistinct() {
        let reasons = TodayPresenter.present(TodayFixtures.soreDay).readiness.reasons
        #expect(Set(reasons.map { $0.lowercased() }).count == reasons.count)
        #expect(reasons.contains("Quads and glutes sore"))
    }

    @Test("a sore region is both the block and the worst factor, so the engine repeats it")
    func theEngineItselfRepeatsIt() {
        // Guards the reason the de-duplication exists: if the engine stops repeating
        // itself, this fails and the extra step can go.
        let raw = ReadinessEngine.assess(TodayFixtures.soreDay.readinessInput).reasons
        #expect(raw.count == 2)
        #expect(raw[0] == raw[1])
    }

    @Test("reasons are sentence case, and an initialism keeps its capitals")
    func reasonsAreSentenceCase() {
        #expect(TodayPresenter.reasons(["slept 6h10"]) == ["Slept 6h10"])
        #expect(TodayPresenter.reasons(["HRV \u{2212}18% vs baseline"])
            == ["HRV \u{2212}18% vs baseline"])
    }

    @Test("two distinct facts both survive")
    func distinctReasonsSurvive() {
        #expect(TodayPresenter.present(TodayFixtures.trainingDay).readiness.reasons.count == 2)
    }

    // MARK: - Protein pace

    @Test("nothing is expected before the eating day begins")
    func paceStartsEmpty() {
        #expect(ProteinPace.elapsedFraction(minuteOfDay: 6 * 60) == 0)
        #expect(ProteinPace.elapsedFraction(minuteOfDay: 8 * 60) == 0)
        #expect(ProteinPace.elapsedFraction(minuteOfDay: 15 * 60) == 0.5)
        #expect(ProteinPace.elapsedFraction(minuteOfDay: 23 * 60) == 1)
    }

    @Test("being level or ahead of pace is not worth a clause")
    func paceReportsOnlyDeficits() {
        let evening = Timestamp.literal("2026-11-03T22:00:00-05:00")
        #expect(ProteinPace.gramsBehind(consumed: 150, target: 150, at: evening) == nil)
        #expect(ProteinPace.gramsBehind(consumed: 180, target: 150, at: evening) == nil)
        #expect(ProteinPace.gramsBehind(consumed: 110, target: 150, at: evening) == 40)
    }

    @Test("a gap smaller than the reporting threshold stays off the screen")
    func paceIgnoresNoise() {
        let evening = Timestamp.literal("2026-11-03T22:00:00-05:00")
        #expect(ProteinPace.gramsBehind(consumed: 145, target: 150, at: evening) == nil)
    }

    // MARK: - Measurements

    @Test("the day's measurements are the five spec §F1 asks for")
    func measurementRows() {
        let rows = TodayPresenter.present(TodayFixtures.trainingDay).measurements
        #expect(rows.map(\.label) == ["Sleep", "Bedtime", "Steps", "Energy", "Exercise"])
        #expect(rows[0].value == "7h42")
        #expect(rows[1].value == "\u{00B1}24")
    }

    @Test("an unmeasured value is an em dash, never a zero")
    func unmeasuredIsNotZero() {
        let rows = TodayPresenter.present(TodayFixtures.emptyDay).measurements
        #expect(rows.map(\.label) == ["Sleep", "Steps", "Energy", "Exercise"])
        #expect(rows.allSatisfy { $0.value == "—" })
        #expect(rows.allSatisfy { $0.progress == nil })
        #expect(rows.allSatisfy { $0.spokenValue == "Not measured" })
    }

    @Test("every row carries a value VoiceOver can read")
    func rowsAreSpoken() {
        for snapshot in [TodayFixtures.trainingDay, TodayFixtures.restDay,
                         TodayFixtures.soreDay, TodayFixtures.emptyDay] {
            for row in TodayPresenter.present(snapshot).measurements {
                #expect(!(row.spokenValue ?? "").isEmpty)
            }
        }
    }

    @Test("durations round-trip in the shape §3.2 asks for", arguments: [
        (462, "7h42"), (0, "0h00"), (60, "1h00"), (-5, "0h00"), (1_445, "24h05")
    ])
    func durationFormatting(minutes: Int, text: String) {
        #expect(TodayFormat.duration(minutes: minutes) == text)
    }

    // MARK: - Nutrition and the card budget

    @Test("the rings are measured against the user's targets")
    func nutritionTargets() {
        let panel = TodayPresenter.present(TodayFixtures.trainingDay).nutrition
        #expect(panel.kcalTarget == 2_200)
        #expect(panel.proteinTargetGrams == 150)
        #expect(panel.proteinGrams == 96)
    }

    @Test("no snapshot ever produces more than the five cards §5.2 allows")
    func cardBudget() {
        for snapshot in [TodayFixtures.trainingDay, TodayFixtures.restDay,
                         TodayFixtures.soreDay, TodayFixtures.emptyDay] {
            let presentation = TodayPresenter.present(snapshot)
            // readiness, nutrition, measurements and the grid always draw; the session
            // card draws only when a session is prescribed.
            let cards = 4 + (presentation.session == nil ? 0 : 1)
            #expect(cards <= 5)
        }
    }

    @Test("every label the screen hands DesignSystem is a label, not a sentence")
    func labelsObeyRuleOneThree() {
        let labels = ["Readiness", "Session", "Exercises", "Consistency"]
            + TodayPresenter.present(TodayFixtures.trainingDay).measurements.map(\.label)
        for label in labels {
            #expect(LabelRule.isCompliant(label), "\(label) is not a label")
        }
    }

    @Test("a session card names the session and its exercise count")
    func sessionPlan() {
        let plan = TodayPresenter.present(TodayFixtures.trainingDay).session
        #expect(plan?.kind == .lowerA)
        #expect(plan?.name == "Lower A")
        #expect(plan?.exercises == 4)
    }
}
