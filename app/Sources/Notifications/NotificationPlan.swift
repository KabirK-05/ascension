import AscensionCore
import Foundation
import SystemSurfaces

/// The four notifications, and nothing else, ever.
///
/// `docs/SPEC.md` §F8 names exactly four and then says "Nothing else". So the set is a
/// closed enum rather than a list of calls, every one of them is **conditional** on having
/// something to say, and there is no code path that can add a fifth.
///
/// Pure on purpose: what fires, when, and with what words is decided here over a value and
/// a clock, so every rule below is a test rather than something you find out at 8 pm.
enum NotificationSlot: String, CaseIterable, Sendable {
    case morningReadiness
    case proteinShortfall
    case trainingCheck
    case sundayReview

    /// The identifier the request carries. Stable, so rescheduling replaces rather than
    /// stacks.
    var identifier: String { "ascension.notification.\(rawValue)" }
}

/// One notification, already decided. A `Date`, not a rule, so the caller only builds a
/// trigger.
struct PlannedNotification: Hashable, Sendable {
    var slot: NotificationSlot
    var title: String
    var body: String
    var fireAt: Date
}

/// Everything the four rules read.
struct NotificationFacts: Sendable {
    var today: CalendarDate
    var now: Date
    var timeZone: TimeZone
    var readinessScore: Int?
    var verdict: ReadinessVerdict?
    /// `nil` on a rest day, which is why the 6:30 check cannot fire on one.
    var sessionName: String?
    var sessionDone: Bool
    var proteinRemainingG: Double
    /// The week's one win, when the Sunday review has been written. `nil` otherwise, and a
    /// review with nothing to say is not sent.
    var reviewLine: String?
}

enum NotificationPlan {
    static let morningHour = 7
    static let proteinHour = 20
    static let trainingHour = 18
    static let trainingMinute = 30
    static let reviewHour = 19

    /// ISO-8601 Sunday, matching `WeeklyReview.reviewWeekday`.
    static let reviewWeekday = 7

    /// The most protein a single meal can still close.
    ///
    /// Spec §F8 says the 8 pm nudge fires "if fixable", and this is what fixable means: one
    /// chicken-and-rice dinner is roughly 60–70 g, so a shortfall past this is not a
    /// shortfall a notification can do anything about — and a notification that cannot be
    /// acted on is the kind this app does not send.
    static let fixableCeilingG: Double = 80

    static func isFixable(remainingG: Double) -> Bool {
        remainingG > 0 && remainingG <= fixableCeilingG
    }

    /// Everything to schedule from here, in fire order.
    static func plan(_ facts: NotificationFacts) -> [PlannedNotification] {
        [morning(facts), protein(facts), training(facts), review(facts)]
            .compactMap { $0 }
            .sorted { $0.fireAt < $1.fireAt }
    }

    // MARK: - The four

    /// Readiness, at 7 am. Sent only when the engine has actually scored the day: a morning
    /// notification saying nothing is the clutter §F8 forbids.
    private static func morning(_ facts: NotificationFacts) -> PlannedNotification? {
        guard let score = facts.readinessScore, let verdict = facts.verdict else { return nil }
        guard let fireAt = next(hour: morningHour, minute: 0, facts: facts) else { return nil }
        return PlannedNotification(slot: .morningReadiness,
                                   title: "Readiness",
                                   body: "\(score) — \(SurfaceText.verdict(verdict))",
                                   fireAt: fireAt)
    }

    /// The protein shortfall, at 8 pm, only while one meal still closes it.
    private static func protein(_ facts: NotificationFacts) -> PlannedNotification? {
        guard isFixable(remainingG: facts.proteinRemainingG) else { return nil }
        guard let fireAt = next(hour: proteinHour, minute: 0, facts: facts),
              sameDay(fireAt, as: facts) else { return nil }
        return PlannedNotification(
            slot: .proteinShortfall,
            title: "Protein",
            body: "\(SurfaceText.grams(facts.proteinRemainingG)) to go — a chicken dinner closes it",
            fireAt: fireAt)
    }

    /// The 6:30 pm check, on a training day with nothing recorded yet.
    ///
    /// Only for *today*: a session that is still missing tomorrow evening is tomorrow's
    /// question, and the next refresh will ask it.
    private static func training(_ facts: NotificationFacts) -> PlannedNotification? {
        guard let session = facts.sessionName, !facts.sessionDone else { return nil }
        guard let fireAt = next(hour: trainingHour, minute: trainingMinute, facts: facts),
              sameDay(fireAt, as: facts) else { return nil }
        return PlannedNotification(slot: .trainingCheck,
                                   title: session,
                                   body: "Nothing recorded yet",
                                   fireAt: fireAt)
    }

    /// The Sunday review, on Sunday evening, with the week's own line in it.
    private static func review(_ facts: NotificationFacts) -> PlannedNotification? {
        guard facts.today.isoWeekday == reviewWeekday, let line = facts.reviewLine,
              !line.isEmpty else { return nil }
        guard let fireAt = next(hour: reviewHour, minute: 0, facts: facts),
              sameDay(fireAt, as: facts) else { return nil }
        return PlannedNotification(slot: .sundayReview, title: "Week", body: line, fireAt: fireAt)
    }

    // MARK: - Clock

    /// The next `hour:minute` strictly after `now`, in the user's timezone — today's if it
    /// has not passed, tomorrow's if it has.
    static func next(hour: Int, minute: Int, facts: NotificationFacts) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = facts.timeZone
        var parts = calendar.dateComponents([.year, .month, .day], from: facts.now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        guard let todayAt = calendar.date(from: parts) else { return nil }
        if todayAt > facts.now { return todayAt }
        return calendar.date(byAdding: .day, value: 1, to: todayAt)
    }

    /// Whether a fire time is still on the day the facts describe.
    ///
    /// Three of the four rules read today's numbers — protein eaten, session not yet done —
    /// so a slot that has already passed must not be scheduled for tomorrow with today's
    /// figures in it. The next refresh schedules tomorrow's, with tomorrow's.
    private static func sameDay(_ instant: Date, as facts: NotificationFacts) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = facts.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return parts.year == facts.today.year
            && parts.month == facts.today.month
            && parts.day == facts.today.day
    }
}
