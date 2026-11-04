import AscensionCore
import AscensionEngines
import Foundation

/// Planned versus done (spec §F2).
///
/// Three rules decide every day, and each exists because getting it wrong would lie to a
/// screen whose only job is to answer "am I on program?":
///
/// 1. A workout of the wrong kind on the right day does **not** complete the session. A
///    15-minute walk on a Lower B day is the finisher, not the squats.
/// 2. A day credits **at most one** workout, so two sessions on one day cannot count
///    twice — the second lands in `extras`.
/// 3. A rest day is never completed and never missed. The program planned nothing, so
///    nothing can be owed.
public enum SessionMatcher {

    /// The program's view of `days`, in the order given.
    ///
    /// `blocks` are the user's calendar training blocks. They do not decide whether a day
    /// was completed — HealthKit does — but when a day holds several eligible workouts
    /// the one overlapping the block is the session and the rest are extras.
    public static func days(_ days: [CalendarDate],
                            program: ProgramDocument,
                            today: CalendarDate,
                            sessions: [CompletedSession],
                            blocks: [TrainingBlock] = [],
                            timeZone: TimeZone) -> [TrainingDay] {
        let byDay = Dictionary(grouping: sessions) { TrainDay.of($0.start, timeZone: timeZone) }
        let blocksByDay = Dictionary(grouping: blocks) { TrainDay.of($0.start, timeZone: timeZone) }
        return days.map { date in
            day(date, program: program, today: today,
                sessions: (byDay[date] ?? []).sorted { $0.start < $1.start },
                blocks: blocksByDay[date] ?? [])
        }
    }

    static func day(_ date: CalendarDate,
                    program: ProgramDocument,
                    today: CalendarDate,
                    sessions: [CompletedSession],
                    blocks: [TrainingBlock]) -> TrainingDay {
        let planned = program.kind(forWeekday: date.isoWeekday) ?? .rest
        let name = program.sessions[planned]?.name
        let scheduledStart = blocks.map(\.start).min()

        guard let required = planned.requiredModality else {
            return TrainingDay(date: date, planned: planned, sessionName: name,
                               outcome: .rest, extras: sessions, scheduledStart: scheduledStart)
        }

        let eligible = sessions.filter { $0.modality == required }
        guard let credited = credit(from: eligible, blocks: blocks) else {
            return TrainingDay(date: date, planned: planned, sessionName: name,
                               outcome: date < today ? .missed : .upcoming,
                               extras: sessions, scheduledStart: scheduledStart)
        }
        return TrainingDay(date: date, planned: planned, sessionName: name,
                           outcome: .completed, completedBy: credited,
                           extras: sessions.filter { $0.id != credited.id },
                           scheduledStart: scheduledStart)
    }

    /// The one workout that counts: the one the calendar block was for, else the longest.
    /// Longest rather than first, because a 10-minute false start before the real session
    /// should not be what the week is judged on.
    private static func credit(from eligible: [CompletedSession],
                               blocks: [TrainingBlock]) -> CompletedSession? {
        let intervals = blocks.map(\.interval)
        let overlapping = eligible.filter { session in
            let span = DateInterval(start: session.start, end: max(session.start, session.end))
            return intervals.contains { $0.intersects(span) }
        }
        let candidates = overlapping.isEmpty ? eligible : overlapping
        return candidates.max { lhs, rhs in
            if lhs.durationMinutes != rhs.durationMinutes {
                return lhs.durationMinutes < rhs.durationMinutes
            }
            return lhs.start < rhs.start
        }
    }
}

/// The local day a moment belongs to.
///
/// The contract keys every day on a `YYYY-MM-DD` in the user's timezone, so a workout
/// that starts at 11 pm belongs to that day and not to the UTC one after it.
public enum TrainDay {
    public static func of(_ date: Date, timeZone: TimeZone) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDate(year: parts.year ?? 1970,
                            month: parts.month ?? 1,
                            day: parts.day ?? 1) ?? CalendarDate.literal("1970-01-01")
    }

    /// The Monday-to-Sunday week containing `date`, matching `ProgramDayEntry.weekday`.
    public static func week(containing date: CalendarDate) -> [CalendarDate] {
        let monday = date.adding(days: -(date.isoWeekday - 1))
        return (0..<ProgramDocument.weekdayCount).map { monday.adding(days: $0) }
    }
}
