import AscensionCore
import AscensionEngines
import DesignSystem
import Foundation
import Testing

@testable import FeatureToday

/// The grid is wired to the contract, and this is the proof.
///
/// `DesignSystem` derives a cell's intensity from four measurements; `AscensionCore`
/// stores four booleans computed by ``WinsCalculator``. They are only trustworthy
/// together if they are the same function, so these tests assert that equality rather
/// than assuming it.
@Suite("Consistency grid")
struct ConsistencyMappingTests {
    private let goals = Seed.goalSettings

    private var thresholds: ConsistencyThresholds {
        ConsistencyMapping.thresholds(for: goals.targets)
    }

    @Test("thresholds come from the user's own targets, not the component's defaults")
    func thresholdsFollowTargets() {
        var targets = goals.targets
        targets.proteinMinG = 165
        targets.steps = 12_000
        targets.sleepMinutes = 480
        let mapped = ConsistencyMapping.thresholds(for: targets)
        #expect(mapped.proteinGrams == 165)
        #expect(mapped.steps == 12_000)
        #expect(mapped.sleepHours == 8)
    }

    @Test("a cell's intensity always equals the contract's wins total")
    func intensityMatchesWinsCalculator() {
        for rollup in TodayFixtures.history(endingOn: TodayFixtures.tuesday) {
            let expected = WinsCalculator.wins(for: rollup, goals: goals).total
            #expect(ConsistencyMapping.wins(of: rollup).intensity(against: thresholds) == expected)
        }
    }

    @Test("they still agree on the boundaries of every threshold", arguments: [
        (140.0, 10_000, 450), (139.9, 9_999, 449), (140.1, 10_001, 451), (0.0, 0, 0)
    ])
    func intensityMatchesOnBoundaries(protein: Double, steps: Int, sleep: Int) {
        let rollup = day(protein: protein, steps: steps, sleepMinutes: sleep,
                         training: TrainingRollup(sessionPlanned: .lowerA, sessionDone: true))
        let expected = WinsCalculator.wins(for: rollup, goals: goals).total
        #expect(ConsistencyMapping.wins(of: rollup).intensity(against: thresholds) == expected)
    }

    @Test("an unmeasured value never scores as a win")
    func missingMeasurementsLose() {
        let rollup = day(protein: nil, steps: nil, sleepMinutes: nil,
                         training: TrainingRollup(sessionPlanned: .lowerA))
        let wins = ConsistencyMapping.wins(of: rollup)
        #expect(wins.intensity(against: thresholds) == 0)
        #expect(WinsCalculator.wins(for: rollup, goals: goals).total == 0)
    }

    @Test("a planned rest day with no workout is a session win, a missed session is not")
    func restDayCountsAsTrained() {
        #expect(ConsistencyMapping.outcome(of: TrainingRollup(sessionPlanned: .rest)) == .rest)
        #expect(ConsistencyMapping.outcome(of: TrainingRollup(sessionPlanned: .lowerA)) == .missed)
        #expect(ConsistencyMapping.outcome(
            of: TrainingRollup(sessionPlanned: .lowerA, sessionDone: true)) == .asPlanned)
    }

    @Test("a day with nothing recorded draws as empty rather than as four losses")
    func emptyDaysAreNotTappable() {
        let blank = DayRollup(date: TodayFixtures.tuesday, timezone: Seed.timezone,
                              updatedAt: Timestamp.literal("2026-11-03T07:00:00-05:00"),
                              wins: Wins(session: false, protein: false,
                                         steps: false, sleep: false))
        #expect(!ConsistencyMapping.hasData(blank))
        let calendar = ConsistencyMapping.calendar(timezone: Seed.timezone)
        #expect(ConsistencyMapping.days(from: [blank], calendar: calendar).first?.wins == nil)
    }

    @Test("today is the last cell, part-filled from its live rollup")
    func todayIsInTheGrid() {
        let snapshot = TodayFixtures.trainingDay
        let panel = TodayPresenter.present(snapshot).consistency
        let slots = ConsistencyLayout.slots(for: panel.days,
                                            endingOn: panel.endDate,
                                            calendar: panel.calendar)
        let last = slots.flatMap { $0 }.compactMap { $0 }.last
        #expect(last?.date == panel.endDate)
        #expect(last?.wins == ConsistencyMapping.wins(of: snapshot.today))
    }

    @Test("a stale copy of today in the history loses to the live rollup")
    func todayWinsOverHistory() {
        var snapshot = TodayFixtures.trainingDay
        var stale = snapshot.today
        stale.activity.steps = 0
        stale.nutrition.proteinG = 0
        stale.sleep.asleepMinutes = 0
        snapshot.history.append(stale)
        let panel = TodayPresenter.present(snapshot).consistency
        let slots = ConsistencyLayout.slots(for: panel.days,
                                            endingOn: panel.endDate,
                                            calendar: panel.calendar)
        let last = slots.flatMap { $0 }.compactMap { $0 }.last
        #expect(last?.wins == ConsistencyMapping.wins(of: snapshot.today))
    }

    @Test("the window the screen builds fills the grid's seventeen weeks")
    func windowFillsTheGrid() {
        let panel = TodayPresenter.present(TodayFixtures.trainingDay).consistency
        let slots = ConsistencyLayout.slots(for: panel.days,
                                            endingOn: panel.endDate,
                                            calendar: panel.calendar)
        #expect(slots.count == ConsistencyLayout.weeks)
        let scored = slots.flatMap { $0 }.compactMap { $0?.wins }
        #expect(scored.count >= ConsistencyLayout.weeks * ConsistencyLayout.daysPerWeek / 2)
    }

    private func day(protein: Double?, steps: Int?, sleepMinutes: Int?,
                     training: TrainingRollup) -> DayRollup {
        DayRollup(date: TodayFixtures.tuesday,
                  timezone: Seed.timezone,
                  updatedAt: Timestamp.literal("2026-11-03T23:50:00-05:00"),
                  nutrition: NutritionRollup(proteinG: protein),
                  activity: ActivityRollup(steps: steps),
                  sleep: SleepRollup(asleepMinutes: sleepMinutes),
                  training: training,
                  wins: Wins(session: false, protein: false, steps: false, sleep: false))
    }
}
