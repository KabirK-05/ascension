import AscensionCore
import FeatureTrends
import Foundation
import OSLog
import SystemSurfaces
import UserNotifications

/// Puts ``NotificationPlan``'s four decisions in front of `UNUserNotificationCenter`.
///
/// Everything conditional is in the plan; this only asks, cancels and submits. Cancelling
/// first is the point: the four identifiers are fixed, so a reschedule **replaces** them
/// and a condition that stopped being true — the protein was eaten, the session landed —
/// removes a pending notification rather than letting it fire anyway.
///
/// Authorization is asked for the first time there is something to schedule, so the system
/// sheet appears because the app has a notification to send and not because it launched.
@MainActor
struct NotificationScheduler {
    private let composition: AppComposition
    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.kabirkumar.ascension", category: "notifications")

    init(composition: AppComposition, center: UNUserNotificationCenter = .current()) {
        self.composition = composition
        self.center = center
    }

    /// Re-decides all four and replaces what is pending.
    func reschedule(now: Date = Date()) async {
        let facts = await facts(now: now)
        let planned = NotificationPlan.plan(facts)

        center.removePendingNotificationRequests(
            withIdentifiers: NotificationSlot.allCases.map(\.identifier))

        guard !planned.isEmpty, await authorized() else { return }

        for notification in planned {
            await submit(notification, timeZone: facts.timeZone)
        }
        logger.info("scheduled \(planned.count, privacy: .public) notifications")
    }

    /// The day as the ledger has it, plus the Sunday review's own line on the day it
    /// covers.
    private func facts(now: Date) async -> NotificationFacts {
        let report = await composition.refresher.refresh(now: now)
        let program = report.program
        let planned = program.kind(forWeekday: report.today.date.isoWeekday)
        let target = Double(report.goals.targets.proteinG)
        let eaten = report.today.nutrition.proteinG ?? 0

        return NotificationFacts(
            today: report.today.date,
            now: now,
            timeZone: report.timeZone,
            readinessScore: report.today.readiness?.score,
            verdict: report.today.readiness?.verdict,
            sessionName: planned.flatMap { program.sessions[$0]?.name },
            sessionDone: report.today.training.sessionDone,
            proteinRemainingG: max(target - eaten, 0),
            reviewLine: await reviewLine(report: report))
    }

    /// ASC-15 built the review and exposed `WeeklyReview.text(for:)` for exactly this. The
    /// notification carries the week's **win**; the focus stays on the card, because a
    /// notification is one line and the second one would be the subtitle §1.1 bans.
    private func reviewLine(report: DayRefreshService.Report) async -> String? {
        guard report.today.date.isoWeekday == NotificationPlan.reviewWeekday else { return nil }
        let snapshot = TrendsSnapshot(clock: report.clock,
                                      goals: report.goals,
                                      program: report.program,
                                      flags: composition.flags.document,
                                      history: await composition.ledger.load().all)
        return await WeeklyReview.text(for: snapshot)?.win
    }

    /// Asks once; a refusal is remembered by the system and answered here without a second
    /// prompt. A denied app simply sends nothing — there is no screen that complains.
    private func authorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    private func submit(_ notification: PlannedNotification, timeZone: TimeZone) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: notification.fireAt)
        parts.timeZone = timeZone

        let request = UNNotificationRequest(
            identifier: notification.slot.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
            try await center.add(request)
        } catch {
            let slot = notification.slot.rawValue
            logger.info("\(slot, privacy: .public) not scheduled: \(error, privacy: .public)")
        }
    }
}
