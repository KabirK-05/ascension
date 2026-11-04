import AscensionCore
import AscensionEngines
import Foundation

/// How much of the week the program asked for actually happened.
public struct WeekAdherence: Hashable, Sendable {
    /// Planned training days that have already come round. A Monday morning is not 0 %
    /// of the week — it is 0 of 0 so far.
    public var planned: Int
    public var completed: Int
    public var missed: Int
    public var upcoming: Int

    public init(planned: Int = 0, completed: Int = 0, missed: Int = 0, upcoming: Int = 0) {
        self.planned = planned
        self.completed = completed
        self.missed = missed
        self.upcoming = upcoming
    }

    /// `nil` until the week has asked for something, rather than a misleading 0 % or
    /// 100 %.
    public var fraction: Double? {
        guard planned > 0 else { return nil }
        return Double(completed) / Double(planned)
    }

    public var percent: Int? {
        fraction.map { Int(($0 * 100).rounded()) }
    }

    /// Sessions the week still holds: what is left to do, not what was missed.
    public var remaining: Int { upcoming }
}

public enum Adherence {

    /// Adherence over the days given. Only elapsed planned days count against it.
    public static func week(_ days: [TrainingDay]) -> WeekAdherence {
        var adherence = WeekAdherence()
        for day in days {
            switch day.outcome {
            case .completed:
                adherence.planned += 1
                adherence.completed += 1
            case .missed:
                adherence.planned += 1
                adherence.missed += 1
            case .upcoming:
                adherence.upcoming += 1
            case .rest:
                continue
            }
        }
        return adherence
    }

    /// Sessions completed in a row, counting back from the most recent elapsed day.
    ///
    /// Rest days neither extend nor break a streak — the program planned nothing, so
    /// nothing happened or failed to. A day still ahead is not yet evidence either way,
    /// so the count starts at the last day that has already been decided.
    public static func streak(_ days: [TrainingDay]) -> Int {
        var streak = 0
        for day in days.reversed() {
            switch day.outcome {
            case .completed: streak += 1
            case .missed: return streak
            case .rest, .upcoming: continue
            }
        }
        return streak
    }
}
