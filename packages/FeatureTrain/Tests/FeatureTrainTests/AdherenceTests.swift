import AscensionCore
import Foundation
import Testing

@testable import FeatureTrain

@Suite("adherence and streak")
struct AdherenceTests {
    private func day(_ raw: String, _ outcome: DayOutcome,
                     planned: SessionKind = .upperA) -> TrainingDay {
        TrainingDay(date: Fixture.date(raw), planned: planned, outcome: outcome)
    }

    @Test("only elapsed planned days count against the week")
    func upcomingDaysAreNotHeldAgainstTheWeek() {
        let adherence = Adherence.week([
            day("2026-11-02", .completed),
            day("2026-11-03", .completed),
            day("2026-11-04", .rest, planned: .rest),
            day("2026-11-05", .upcoming),
            day("2026-11-06", .upcoming)
        ])
        #expect(adherence.planned == 2)
        #expect(adherence.completed == 2)
        #expect(adherence.upcoming == 2)
        #expect(adherence.percent == 100)
    }

    @Test("a missed day is the only thing that lowers the percentage")
    func missedDaysLowerThePercentage() {
        let adherence = Adherence.week([
            day("2026-11-02", .completed),
            day("2026-11-03", .missed),
            day("2026-11-05", .completed),
            day("2026-11-06", .completed)
        ])
        #expect(adherence.planned == 4)
        #expect(adherence.missed == 1)
        #expect(adherence.percent == 75)
    }

    @Test("a week that has asked for nothing yet has no percentage, not nought percent")
    func anUnaskedWeekHasNoPercentage() {
        let adherence = Adherence.week([day("2026-11-02", .upcoming), day("2026-11-03", .rest)])
        #expect(adherence.fraction == nil)
        #expect(adherence.percent == nil)
    }

    @Test("a streak runs through rest days and stops at a missed session")
    func streakSkipsRestAndBreaksOnAMiss() {
        let days = [
            day("2026-10-26", .completed),
            day("2026-10-27", .missed),
            day("2026-10-29", .completed),
            day("2026-11-01", .rest, planned: .rest),
            day("2026-11-02", .completed),
            day("2026-11-03", .completed)
        ]
        #expect(Adherence.streak(days) == 3)
    }

    @Test("a day still ahead neither extends nor ends a streak")
    func upcomingDaysDoNotCount() {
        let days = [
            day("2026-11-02", .completed),
            day("2026-11-03", .completed),
            day("2026-11-05", .upcoming)
        ]
        #expect(Adherence.streak(days) == 2)
    }

    @Test("a streak that starts on a miss is nought, not one")
    func aMissEndsItImmediately() {
        #expect(Adherence.streak([day("2026-11-02", .completed), day("2026-11-03", .missed)]) == 0)
    }
}
