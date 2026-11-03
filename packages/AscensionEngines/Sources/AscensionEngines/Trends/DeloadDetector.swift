import AscensionCore
import Foundation

/// Where the current block sits relative to its deload.
public enum DeloadStatus: Hashable, Sendable {
    /// A deload is already running (`program.deload.active`).
    case active

    /// Still inside the block.
    case notDue(weeksIntoBlock: Int)

    /// The cadence week has arrived — this is the prompt (spec §F6).
    case due(weeksIntoBlock: Int)

    /// The cadence week has passed without a deload.
    case overdue(weeksIntoBlock: Int)

    /// Weeks into the block, however the block is going.
    public var weeksIntoBlock: Int? {
        switch self {
        case .active: return nil
        case .notDue(let weeks), .due(let weeks), .overdue(let weeks): return weeks
        }
    }

    /// Whether the user should be prompted.
    public var shouldPrompt: Bool {
        switch self {
        case .due, .overdue: return true
        case .active, .notDue: return false
        }
    }
}

/// Deload detection (spec §F6: "deload prompt when week 5–6 of a block is reached").
///
/// The cadence is data, not code: it comes from `goalSettings.deloadEveryWeeks`, which
/// the seed sets to 5 — so the prompt fires in week 5 and keeps firing through week 6 and
/// beyond until a deload is actually run. Spec §3's "every 4–6 weeks" is the range the
/// setting may be configured across, not a second rule.
public enum DeloadDetector {
    public static func status(program: ProgramDocument,
                              goals: GoalSettingsDocument,
                              asOf: CalendarDate) -> DeloadStatus {
        if program.deload.active { return .active }
        let weeks = weeksIntoBlock(start: goals.programStartDate, asOf: asOf)
        let cadence = goals.deloadEveryWeeks
        // A cadence of zero or less configures no deload at all; there is nothing to be
        // due.
        guard cadence > 0 else { return .notDue(weeksIntoBlock: weeks) }
        if weeks > cadence { return .overdue(weeksIntoBlock: weeks) }
        if weeks == cadence { return .due(weeksIntoBlock: weeks) }
        return .notDue(weeksIntoBlock: weeks)
    }

    /// Week 1 is the first seven days of the block, so the start date itself is week 1.
    /// A date before the block starts is week 0.
    public static func weeksIntoBlock(start: CalendarDate, asOf: CalendarDate) -> Int {
        let days = start.days(until: asOf)
        guard days >= 0 else { return 0 }
        return days / 7 + 1
    }
}
