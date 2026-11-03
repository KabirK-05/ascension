import AscensionCore
import Foundation

/// A training block the user put in their calendar.
///
/// EventKit lives in the app shell; this is the shape it hands over. The title is kept
/// because a block named for a session is a stronger signal than a block that merely
/// sits on the right day.
public struct TrainingBlock: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date

    public init(id: String, title: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }
}

/// Where one day of the program stands.
public enum DayOutcome: String, Hashable, Sendable, CaseIterable {
    /// Planned, and a workout of the right kind landed.
    case completed
    /// Planned, the day is over, and nothing of the right kind landed.
    case missed
    /// The program planned nothing. Not a failure, and a win in its own right (§6.2).
    case rest
    /// Planned, and still ahead — today counts until the day is over.
    case upcoming
}

/// One day of the program week, with what the program asked for and what Apple recorded.
public struct TrainingDay: Hashable, Sendable, Identifiable {
    public var date: CalendarDate
    public var planned: SessionKind
    public var sessionName: String?
    public var outcome: DayOutcome
    /// The one workout credited with completing the day. Never more than one, however
    /// many workouts the day holds.
    public var completedBy: CompletedSession?
    /// Everything else recorded that day: the finisher walk, a second session, a workout
    /// of the wrong kind on a lifting day.
    public var extras: [CompletedSession]
    /// When the calendar said the session would start, if a block was found.
    public var scheduledStart: Date?

    public init(date: CalendarDate, planned: SessionKind, sessionName: String? = nil,
                outcome: DayOutcome, completedBy: CompletedSession? = nil,
                extras: [CompletedSession] = [], scheduledStart: Date? = nil) {
        self.date = date
        self.planned = planned
        self.sessionName = sessionName
        self.outcome = outcome
        self.completedBy = completedBy
        self.extras = extras
        self.scheduledStart = scheduledStart
    }

    public var id: String { date.rawValue }

    /// Every workout the day holds, credited one first.
    public var allSessions: [CompletedSession] {
        (completedBy.map { [$0] } ?? []) + extras
    }
}
