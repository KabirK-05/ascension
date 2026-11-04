import Foundation

/// One win and one focus, in the user's own units (spec §F7).
///
/// Two short lines and nothing else. The review's *numbers* are never generated — the
/// card draws them from ``WeeklyReviewFacts`` — so a model can only ever phrase a fact
/// that is already true, never invent one.
public struct WeeklyReviewText: Hashable, Sendable {
    /// What went right, stated as a measurement.
    public let win: String

    /// The one thing to change, stated as a measurement.
    public let focus: String

    /// Whether the on-device model wrote this, or the templates did.
    public let source: Source

    public enum Source: String, Hashable, Sendable {
        case foundationModels
        case template
    }

    public init(win: String, focus: String, source: Source) {
        self.win = win
        self.focus = focus
        self.source = source
    }
}

/// Writes the two lines of a weekly review.
public protocol WeeklyReviewWriter: Sendable {
    func write(_ facts: WeeklyReviewFacts) async -> WeeklyReviewText?
}

/// The review the app can always produce.
///
/// Deterministic, offline, and the fallback whenever Foundation Models is switched off,
/// unavailable, or declines (spec §F7). Both lines are facts with units — never
/// encouragement, which `docs/DESIGN_RULES.md` §1.2 bans even here.
public struct TemplateReviewWriter: WeeklyReviewWriter {
    public init() {}

    public func write(_ facts: WeeklyReviewFacts) async -> WeeklyReviewText? {
        WeeklyReviewText(win: Self.win(facts), focus: Self.focus(facts), source: .template)
    }

    /// The best fact of the week, in a fixed order of preference: sessions first, because
    /// the program is the thing being adhered to, then the trend, then the protein floor.
    static func win(_ facts: WeeklyReviewFacts) -> String {
        if facts.sessionsPlanned > 0, facts.sessionsCompleted >= facts.sessionsPlanned {
            return "\(facts.sessionsCompleted) of \(facts.sessionsPlanned) sessions done"
        }
        if let rate = facts.weightRateKgPerWeek, rate < 0 {
            return "down \(TrendsFormat.decimal(abs(rate), places: 2)) kg/week"
        }
        if facts.proteinHitRatePct >= Self.hitRateSplitPct {
            return "\(TrendsFormat.percent(facts.proteinHitRatePct)) of days over "
                + "\(facts.proteinFloorG) g protein"
        }
        if facts.sessionsCompleted > 0 {
            return "\(facts.sessionsCompleted) of \(facts.sessionsPlanned) sessions done"
        }
        return "\(TrendsFormat.percent(facts.proteinHitRatePct)) of days over "
            + "\(facts.proteinFloorG) g protein"
    }

    /// The weakest fact, in the order the program cares about: a missed session, then a
    /// stalled trend, then the protein floor, then sleep.
    static func focus(_ facts: WeeklyReviewFacts) -> String {
        if facts.deload.shouldPrompt, let weeks = facts.deload.weeksIntoBlock {
            return "week \(weeks) of the block — deload due"
        }
        let missed = facts.sessionsPlanned - facts.sessionsCompleted
        if missed > 0 {
            return "\(missed) of \(facts.sessionsPlanned) sessions missed"
        }
        if let suggestion = facts.suggestion {
            return "\(suggestion.reason) — \(suggestion.suggestedKcal) kcal suggested"
        }
        if facts.proteinHitRatePct < Self.hitRateSplitPct {
            return "\(TrendsFormat.percent(100 - facts.proteinHitRatePct)) of days under "
                + "\(facts.proteinFloorG) g protein"
        }
        if let minutes = facts.sleepMeanMinutes, minutes < Double(facts.sleepTargetMinutes) {
            return "sleeping \(TrendsFormat.duration(minutes: Int(minutes.rounded())))"
        }
        if let ratio = facts.acuteChronicRatio, facts.band == .caution || facts.band == .highRisk {
            return "load ratio \(TrendsFormat.decimal(ratio, places: 2))"
        }
        if let remaining = facts.kgToGoal {
            return "\(TrendsFormat.decimal(remaining, places: 1)) kg to "
                + "\(TrendsFormat.decimal(facts.goalWeightKg, places: 1)) kg"
        }
        return "\(facts.sessionsCompleted) of \(facts.sessionsPlanned) sessions done"
    }

    /// Where a hit-rate stops being the week's best fact and starts being its worst.
    ///
    /// Presentation only: it picks which true sentence to print and changes no number.
    /// Every threshold that decides anything lives in `AscensionEngines`.
    static let hitRateSplitPct: Double = 70
}
