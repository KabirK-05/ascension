import AscensionCore
import Foundation
import Testing

@testable import Ascension

/// §F8 names four notifications and then says "Nothing else". These are the conditions
/// under which each of the four may fire — the part that decides whether the phone buzzes
/// at 8 pm, which is exactly the kind of rule that should not be discovered at 8 pm.
@Suite("notification plan")
struct NotificationPlanTests {
    private let zone = TimeZone(identifier: "America/Toronto") ?? .gmt

    /// A Tuesday, which the seeded program trains on, at 09:00 local.
    private func facts(hour: Int = 9,
                       day: String = "2026-11-03",
                       score: Int? = 74,
                       session: String? = "Lower A",
                       sessionDone: Bool = false,
                       proteinRemaining: Double = 62,
                       review: String? = nil) -> NotificationFacts {
        var parts = DateComponents()
        parts.timeZone = zone
        let date = CalendarDate.literal(day)
        parts.year = date.year
        parts.month = date.month
        parts.day = date.day
        parts.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return NotificationFacts(
            today: date,
            now: calendar.date(from: parts) ?? Date(),
            timeZone: zone,
            readinessScore: score,
            verdict: score == nil ? nil : .trainAsPlanned,
            sessionName: session,
            sessionDone: sessionDone,
            proteinRemainingG: proteinRemaining,
            reviewLine: review)
    }

    private func slots(_ facts: NotificationFacts) -> Set<NotificationSlot> {
        Set(NotificationPlan.plan(facts).map(\.slot))
    }

    @Test("a training morning with a shortfall schedules three, and never a fourth")
    func theFourAreClosed() {
        let planned = slots(facts())
        #expect(planned == [.morningReadiness, .proteinShortfall, .trainingCheck])
        #expect(planned.isSubset(of: Set(NotificationSlot.allCases)))
    }

    @Test("an unscored morning says nothing rather than saying nothing useful")
    func noReadinessNoNotification() {
        #expect(!slots(facts(score: nil)).contains(.morningReadiness))
    }

    @Test("the readiness body is the score and the verdict, with no third clause")
    func readinessBody() throws {
        let planned = NotificationPlan.plan(facts())
        let morning = try #require(planned.first { $0.slot == .morningReadiness })
        #expect(morning.title == "Readiness")
        #expect(morning.body == "74 — Train as planned")
    }

    @Test("a shortfall one meal cannot close is not a notification")
    func unfixableShortfallIsSilent() {
        #expect(!slots(facts(proteinRemaining: 120)).contains(.proteinShortfall))
        #expect(NotificationPlan.isFixable(remainingG: 120) == false)
    }

    @Test("a target already met is not a shortfall")
    func metTargetIsSilent() {
        #expect(!slots(facts(proteinRemaining: 0)).contains(.proteinShortfall))
    }

    @Test("the shortfall body is the spec's own sentence")
    func shortfallBody() throws {
        let protein = try #require(
            NotificationPlan.plan(facts()).first { $0.slot == .proteinShortfall })
        #expect(protein.body == "62 g to go — a chicken dinner closes it")
    }

    @Test("a workout that already landed cancels the evening check")
    func completedSessionIsSilent() {
        #expect(!slots(facts(sessionDone: true)).contains(.trainingCheck))
    }

    @Test("a rest day never gets the evening check")
    func restDayIsSilent() {
        #expect(!slots(facts(session: nil)).contains(.trainingCheck))
    }

    @Test("a slot that has passed is not rescheduled for tomorrow with today's numbers")
    func passedSlotsAreNotCarriedOver() {
        let evening = slots(facts(hour: 22))
        #expect(!evening.contains(.proteinShortfall))
        #expect(!evening.contains(.trainingCheck))
        // The morning one is tomorrow's by nature, so it still stands.
        #expect(evening.contains(.morningReadiness))
    }

    @Test("the Sunday review fires only on Sunday, and only with a line to carry")
    func sundayReview() {
        // 2026-11-08 is a Sunday.
        #expect(slots(facts(day: "2026-11-08", review: "Protein averaged 151 g"))
            .contains(.sundayReview))
        #expect(!slots(facts(day: "2026-11-08")).contains(.sundayReview))
        #expect(!slots(facts(review: "Protein averaged 151 g")).contains(.sundayReview))
    }

    @Test("every notification lands at its own hour in the user's timezone")
    func fireTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let planned = NotificationPlan.plan(facts())
        for notification in planned {
            let hour = calendar.component(.hour, from: notification.fireAt)
            switch notification.slot {
            case .morningReadiness: #expect(hour == NotificationPlan.morningHour)
            case .proteinShortfall: #expect(hour == NotificationPlan.proteinHour)
            case .trainingCheck: #expect(hour == NotificationPlan.trainingHour)
            case .sundayReview: #expect(hour == NotificationPlan.reviewHour)
            }
        }
    }

    @Test("identifiers are stable, so a reschedule replaces rather than stacks")
    func identifiersAreStable() {
        #expect(NotificationSlot.allCases.count == 4)
        #expect(Set(NotificationSlot.allCases.map(\.identifier)).count == 4)
        #expect(NotificationSlot.morningReadiness.identifier
            == "ascension.notification.morningReadiness")
    }
}
