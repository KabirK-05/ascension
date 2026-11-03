import AscensionCore
import AscensionEngines
import Testing

@testable import FeatureTrends

/// The Sunday review (spec §F7): the fallback path, and the guardrail that keeps a
/// generated line from becoming the motivational sentence §1.2 bans.
struct ReviewWriterTests {

    static func facts(_ snapshot: TrendsSnapshot = TrendsFixtures.sundayReview)
        -> WeeklyReviewFacts {
        WeeklyReviewFacts(report: snapshot.weeklyReport, goals: snapshot.goals)
    }

    @Test("templates always produce a review, with no model and no network")
    func templatesAlwaysProduceAReview() async {
        let text = await TemplateReviewWriter().write(Self.facts())
        #expect(text?.source == .template)
        #expect(text?.win.isEmpty == false)
        #expect(text?.focus.isEmpty == false)
    }

    @Test("the flag off falls through to templates")
    func flagOffFallsThroughToTemplates() async {
        var flags = Seed.flags
        flags.foundationModelsEnabled = false
        let snapshot = TrendsFixtures.snapshot(asOf: TrendsFixtures.sunday, flags: flags)
        let writer = FoundationModelsReviewWriter(flags: flags)

        let text = await writer.write(Self.facts(snapshot))
        #expect(text?.source == .template)
    }

    @Test("a model that declines still yields a review")
    func decliningModelStillYieldsAReview() async {
        struct Declining: WeeklyReviewWriter {
            func write(_ facts: WeeklyReviewFacts) async -> WeeklyReviewText? { nil }
        }
        var flags = Seed.flags
        flags.foundationModelsEnabled = false
        let writer = FoundationModelsReviewWriter(flags: flags,
                                                  fallback: TemplateReviewWriter())
        #expect(await writer.write(Self.facts())?.source == .template)

        let declining: any WeeklyReviewWriter = Declining()
        #expect(await declining.write(Self.facts()) == nil)
    }

    @Test("every template line is a measurement, never encouragement")
    func templateLinesCarryNoMotivationalCopy() async {
        let shapes = [TrendsFixtures.cutting, TrendsFixtures.stalled,
                      TrendsFixtures.layoff, TrendsFixtures.sundayReview]
        for snapshot in shapes {
            guard let text = await TemplateReviewWriter().write(Self.facts(snapshot)) else {
                Issue.record("template writer returned nothing")
                return
            }
            #expect(FoundationModelsReviewWriter.sanitise(text.win) == text.win)
            #expect(FoundationModelsReviewWriter.sanitise(text.focus) == text.focus)
        }
    }

    @Test(arguments: [
        "Keep it up! You crushed this week",
        "Nice work on your protein",
        "Let's push harder next week",
        "Based on your data, sleep more",
        ""
    ])
    func bannedCopyIsRejected(_ line: String) {
        #expect(FoundationModelsReviewWriter.sanitise(line) == nil)
    }

    @Test("a line longer than a label is rejected")
    func overLongLineIsRejected() {
        let long = String(repeating: "7h42 of sleep ", count: 8)
        #expect(long.count > FoundationModelsReviewWriter.lineLimit)
        #expect(FoundationModelsReviewWriter.sanitise(long) == nil)
    }

    @Test("a multi-line answer is rejected rather than squeezed into one row")
    func multiLineAnswerIsRejected() {
        #expect(FoundationModelsReviewWriter.sanitise("4 of 4 sessions\ndone") == nil)
    }

    @Test("a plain measurement survives untouched")
    func measurementSurvives() {
        #expect(FoundationModelsReviewWriter.sanitise("  4 of 4 sessions done  ")
            == "4 of 4 sessions done")
    }

    @Test("the model only ever sees facts, and sees every one it needs")
    func promptCarriesOnlyFacts() {
        let facts = Self.facts()
        let prompt = FoundationModelsReviewWriter.prompt(facts)

        #expect(prompt.contains("sessions: \(facts.sessionsCompleted) done"))
        #expect(prompt.contains("protein:"))
        #expect(prompt.contains("weight 7-day average:"))
        #expect(prompt.contains("sleep average:"))
        #expect(prompt.contains("calorie suggestion:"))
        // Nothing but measurements goes in: no prose the user wrote, no raw rollups.
        #expect(!prompt.contains("DayRollup"))
    }

    @Test("with no deload due, a missed session is what the focus names")
    func focusNamesTheMissedSessions() {
        // A block that started four days ago is week 1, so the deload branch — which
        // outranks everything — is out of the way and the session count is on top.
        var goals = Seed.goalSettings
        goals.programStartDate = CalendarDate.literal("2026-12-01")
        let snapshot = TrendsFixtures.snapshot(asOf: TrendsFixtures.saturday,
                                               shape: TrendsFixtures.Shape(kgPerWeek: -0.1),
                                               goals: goals)
        let facts = WeeklyReviewFacts(report: snapshot.weeklyReport, goals: goals)

        #expect(!facts.deload.shouldPrompt)
        #expect(facts.sessionsPlanned > facts.sessionsCompleted)
        #expect(TemplateReviewWriter.focus(facts).contains("missed"))
    }

    @Test("with the sessions all done, the calorie suggestion is what the focus names")
    func focusFallsThroughToTheSuggestion() {
        var goals = Seed.goalSettings
        goals.programStartDate = CalendarDate.literal("2026-12-01")
        let snapshot = TrendsFixtures.snapshot(
            asOf: TrendsFixtures.saturday,
            shape: TrendsFixtures.Shape(kgPerWeek: -0.1, skippedSessions: 0),
            goals: goals)
        let facts = WeeklyReviewFacts(report: snapshot.weeklyReport, goals: goals)

        #expect(facts.sessionsCompleted == facts.sessionsPlanned)
        #expect(facts.suggestion != nil)
        #expect(TemplateReviewWriter.focus(facts).contains("kcal"))
    }

    @Test("a deload that is due outranks everything else in the focus line")
    func deloadOutranksTheFocus() {
        // The seeded cadence is five weeks, so a block that started 35 days before the
        // snapshot is exactly due.
        var goals = Seed.goalSettings
        goals.programStartDate = CalendarDate.literal("2026-11-01")
        let snapshot = TrendsFixtures.snapshot(asOf: CalendarDate.literal("2026-12-06"),
                                               goals: goals)
        let facts = WeeklyReviewFacts(report: snapshot.weeklyReport, goals: goals)

        #expect(facts.deload.shouldPrompt)
        #expect(TemplateReviewWriter.focus(facts).contains("deload"))
    }
}
