import Foundation

/// What counts as a win, per `docs/DESIGN_RULES.md` §6.2.
///
/// `AscensionCore` computes the real daily rollup; this module only renders
/// one, so it defines its own value type and imports nothing.
public struct ConsistencyThresholds: Hashable, Sendable {
    public var proteinGrams: Int
    public var steps: Int
    public var sleepHours: Double

    public init(proteinGrams: Int = 140, steps: Int = 10_000, sleepHours: Double = 7.5) {
        self.proteinGrams = proteinGrams
        self.steps = steps
        self.sleepHours = sleepHours
    }

    public static let standard = ConsistencyThresholds()
}

/// Whether the day's session went to plan. A planned rest day honoured counts
/// exactly as much as a session trained (§6.2.1).
public enum SessionOutcome: String, Hashable, Sendable, CaseIterable {
    case asPlanned
    case rest
    case missed

    public var isWin: Bool { self != .missed }

    /// Two words, no sentence — this is a value, and it obeys §1.3 too.
    public var display: String {
        switch self {
        case .asPlanned: return "As planned"
        case .rest: return "Rest"
        case .missed: return "Missed"
        }
    }
}

/// One day's four measurements. Intensity is derived, never stored, so the
/// grid and the tap-reveal can never disagree.
public struct DayWins: Hashable, Sendable {
    public var session: SessionOutcome
    public var proteinGrams: Int
    public var steps: Int
    public var sleepHours: Double

    public init(session: SessionOutcome, proteinGrams: Int, steps: Int, sleepHours: Double) {
        self.session = session
        self.proteinGrams = proteinGrams
        self.steps = steps
        self.sleepHours = sleepHours
    }

    /// 0...4, one point per win.
    public func intensity(against thresholds: ConsistencyThresholds = .standard) -> Int {
        var score = 0
        if session.isWin { score += 1 }
        if proteinGrams >= thresholds.proteinGrams { score += 1 }
        if steps >= thresholds.steps { score += 1 }
        if sleepHours >= thresholds.sleepHours { score += 1 }
        return score
    }
}

/// A day in the window. `wins` is nil for a day with no data at all, which the
/// grid draws as empty and does not make tappable.
public struct ConsistencyDay: Hashable, Sendable, Identifiable {
    public let date: Date
    public let wins: DayWins?

    public var id: Date { date }

    public init(date: Date, wins: DayWins?) {
        self.date = date
        self.wins = wins
    }
}

/// The 7 × 17 arrangement, as a pure function so it can be tested without a view.
///
/// 17 weeks, not a year: seven rows of a full year do not fit an iPhone's width
/// at the default type size, and a grid that scrolls sideways is not read at a
/// glance (§6.1).
public enum ConsistencyLayout {
    public static let weeks = 17
    public static let daysPerWeek = 7

    /// Columns are weeks, oldest first; rows are weekdays from the calendar's
    /// own first weekday. A slot is nil when it falls after `endDate`, which is
    /// how the final, partial week keeps its alignment.
    public static func slots(
        for days: [ConsistencyDay],
        endingOn endDate: Date,
        calendar: Calendar = .current
    ) -> [[ConsistencyDay?]] {
        let last = calendar.startOfDay(for: endDate)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: last)?.start,
              let origin = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }

        var known: [Date: ConsistencyDay] = [:]
        for day in days {
            known[calendar.startOfDay(for: day.date)] = day
        }

        return (0..<weeks).map { week in
            (0..<daysPerWeek).map { row -> ConsistencyDay? in
                guard let raw = calendar.date(byAdding: .day, value: week * daysPerWeek + row, to: origin)
                else { return nil }
                let date = calendar.startOfDay(for: raw)
                guard date <= last else { return nil }
                return known[date] ?? ConsistencyDay(date: date, wins: nil)
            }
        }
    }
}
