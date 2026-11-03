import AscensionCore
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device writer (spec §F7), with the templates underneath it.
///
/// Three things have to be true before a model writes anything: the `foundationModels`
/// flag is on in the `flags` document, the framework is present, and the system model
/// says it is available. Any one of them failing falls through to
/// ``TemplateReviewWriter`` — so the review always renders, and it renders the same
/// numbers either way.
///
/// What the model is allowed to do is deliberately small. It phrases two lines from a
/// closed set of facts it is handed; it never sees the store, never computes a number,
/// and anything it returns that is not two short factual lines is discarded. The card's
/// figures come from ``WeeklyReviewFacts`` directly and are never generated.
public struct FoundationModelsReviewWriter: WeeklyReviewWriter {
    private let isEnabled: Bool
    private let fallback: any WeeklyReviewWriter

    public init(flags: FlagsDocument, fallback: any WeeklyReviewWriter = TemplateReviewWriter()) {
        self.isEnabled = flags.foundationModelsEnabled
        self.fallback = fallback
    }

    public func write(_ facts: WeeklyReviewFacts) async -> WeeklyReviewText? {
        if isEnabled, let generated = await generate(facts) { return generated }
        return await fallback.write(facts)
    }

    /// The longest a line may be before it has stopped being a label and started being a
    /// paragraph (`docs/DESIGN_RULES.md` §1.1).
    static let lineLimit = 64

    /// A line the model wrote, or `nil` if it is not usable.
    ///
    /// The checks are the guardrail, not a formatter: a line that is empty, over-long,
    /// multi-line, or carries one of the banned motivational patterns §1.2 lists is
    /// dropped, and dropping either line drops the pair.
    static func sanitise(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= lineLimit else { return nil }
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        let lowered = trimmed.lowercased()
        guard !bannedPhrases.contains(where: lowered.contains) else { return nil }
        guard !trimmed.contains("!") else { return nil }
        return trimmed
    }

    /// §1.2's banned copy patterns, lower-cased. A line matching any of them is the
    /// motivational sentence this project is designed against.
    static let bannedPhrases = [
        "keep it up", "nice work", "great job", "well done", "you've got this",
        "let's", "let us", "here's your", "here is your", "your daily", "track your",
        "based on your", "we noticed", "tap to", "swipe to", "proud", "crush",
        "amazing", "awesome", "fantastic", "keep going", "stay strong"
    ]

    // MARK: - Generation

#if canImport(FoundationModels)
    @available(iOS 26, *)
    private func session() -> LanguageModelSession? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        return LanguageModelSession(instructions: Self.instructions)
    }

    private func generate(_ facts: WeeklyReviewFacts) async -> WeeklyReviewText? {
        guard #available(iOS 26, *), let session = session() else { return nil }
        do {
            let response = try await session.respond(to: Self.prompt(facts),
                                                     generating: GeneratedReview.self)
            guard let win = Self.sanitise(response.content.win),
                  let focus = Self.sanitise(response.content.focus) else { return nil }
            return WeeklyReviewText(win: win, focus: focus, source: .foundationModels)
        } catch {
            return nil
        }
    }

    static let instructions = """
        You restate training and nutrition numbers for one week. You are not a coach.

        Write exactly two lines, each under \(lineLimit) characters:
        - win: the week's strongest number, with its unit.
        - focus: the one number to change next week, with its unit.

        Every line must be a measurement taken from the facts you are given. Never add a
        number that is not there, never estimate, never give advice, never encourage, and
        never use an exclamation mark. Lower case, no final full stop.

        Example win: "4 of 4 sessions done". Example focus: "2 nights under 7h30".
        """
#else
    private func generate(_ facts: WeeklyReviewFacts) async -> WeeklyReviewText? { nil }

    static let instructions = ""
#endif

    /// The facts, as the model receives them: a flat list of measurements and nothing
    /// else. No store, no history, no free text the user wrote.
    static func prompt(_ facts: WeeklyReviewFacts) -> String {
        var lines = [
            "week ending: \(facts.weekEnding.rawValue)",
            "sessions: \(facts.sessionsCompleted) done of \(facts.sessionsPlanned) planned",
            "protein: \(TrendsFormat.percent(facts.proteinHitRatePct)) of days at or over "
                + "\(facts.proteinFloorG) g"
        ]
        if let average = facts.weightAverageKg {
            lines.append("weight 7-day average: \(TrendsFormat.decimal(average)) kg")
        }
        if let rate = facts.weightRateKgPerWeek {
            lines.append("weight rate: \(TrendsFormat.decimal(rate, places: 2)) kg/week")
        }
        if let remaining = facts.kgToGoal {
            lines.append("to goal of \(TrendsFormat.decimal(facts.goalWeightKg)) kg: "
                + "\(TrendsFormat.decimal(remaining)) kg")
        }
        if let minutes = facts.sleepMeanMinutes {
            lines.append("sleep average: \(TrendsFormat.duration(minutes: Int(minutes.rounded()))) "
                + "against a target of \(TrendsFormat.duration(minutes: facts.sleepTargetMinutes))")
        }
        if let suggestion = facts.suggestion {
            lines.append("calorie suggestion: \(suggestion.suggestedKcal) kcal, "
                + "currently \(suggestion.currentKcal) kcal, \(suggestion.reason)")
        }
        if let ratio = facts.acuteChronicRatio {
            lines.append("acute:chronic load ratio: \(TrendsFormat.decimal(ratio, places: 2))")
        }
        if facts.deload.shouldPrompt, let weeks = facts.deload.weeksIntoBlock {
            lines.append("deload due: week \(weeks) of the block")
        }
        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
/// The only shape the model may answer in.
@available(iOS 26, *)
@Generable
struct GeneratedReview {
    @Guide(description: "The week's strongest number with its unit, under 64 characters.")
    var win: String

    @Guide(description: "The one number to change next week with its unit, under 64 characters.")
    var focus: String
}
#endif
