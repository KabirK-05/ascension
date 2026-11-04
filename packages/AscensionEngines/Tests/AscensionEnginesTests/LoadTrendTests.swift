import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

@Suite("training load, the acute:chronic ratio and the layoff warning")
struct LoadTrendTests {
    static let asOf = Fix.date("2026-12-07")

    @Test("the thresholds are the documented bands")
    func thresholdsArePinned() {
        #expect(LoadThresholds.acuteWindowDays == 7)
        #expect(LoadThresholds.chronicWindowDays == 28)
        #expect(LoadThresholds.detrainingBelow == 0.8)
        #expect(LoadThresholds.optimalBelow == 1.3)
        #expect(LoadThresholds.cautionBelow == 1.5)
        #expect(LoadThresholds.layoffDays == 7)
    }

    @Test("bands sit exactly on their boundaries: at, just below, just above",
          arguments: [(0.0, AcwrBand.detraining), (0.79, .detraining), (0.8, .optimal),
                      (1.0, .optimal), (1.29, .optimal), (1.3, .caution),
                      (1.49, .caution), (1.5, .highRisk), (3.0, .highRisk)])
    func bandBoundaries(ratio: Double, expected: AcwrBand) {
        #expect(LoadTrendEngine.band(for: ratio) == expected)
    }

    @Test("a steady four weeks sits at a ratio of one")
    func steadyTrainingIsOptimal() {
        let history = loadEveryDay(1_000, days: 28)
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.acuteLoadAu == 7_000)
        #expect(trend.chronicLoadAu == 7_000)
        #expect(trend.acuteChronicRatio == 1)
        #expect(trend.band == .optimal)
        #expect(!trend.spikeAfterLayoff)
    }

    @Test("a hard week on a steady base pushes the ratio up")
    func spikeWeek() {
        var history = loadEveryDay(1_000, days: 28)
        // Double the most recent week.
        history = history.map { day in
            day.date.days(until: Self.asOf) < 7
                ? Fix.rollup(date: day.date, loadAu: 2_000,
                             workouts: [Fix.workout(on: day.date)])
                : day
        }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.acuteLoadAu == 14_000)
        #expect((trend.acuteChronicRatio ?? 0) > LoadThresholds.cautionBelow)
        #expect(trend.band == .highRisk)
    }

    @Test("a quiet week on a steady base reads as detraining")
    func quietWeek() {
        var history = loadEveryDay(1_000, days: 28)
        history = history.map { day in
            day.date.days(until: Self.asOf) < 7 ? Fix.rollup(date: day.date, loadAu: 0) : day
        }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.acuteLoadAu == 0)
        #expect(trend.band == .detraining)
    }

    @Test("weekly totals are reported one per week, oldest first")
    func weeklySeries() {
        let history = loadEveryDay(1_000, days: 28)
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.weeklyLoadAu.count == 4)
        #expect(trend.weeklyLoadAu.allSatisfy { $0.value == 7_000 })
        #expect(trend.weeklyLoadAu.last?.date == Self.asOf)
        #expect(trend.weeklyLoadAu.map(\.date) == trend.weeklyLoadAu.map(\.date).sorted())
    }

    @Test("no chronic load means no ratio rather than a division by zero")
    func noChronicLoad() {
        let trend = LoadTrendEngine.trend(history: [], asOf: Self.asOf)
        #expect(trend.chronicLoadAu == 0)
        #expect(trend.acuteChronicRatio == nil)
        #expect(trend.band == nil)
    }

    @Test("returning to training on no base at all is a spike")
    func returningFromNothing() {
        // Spec §2: the user is returning after a two-week gap, so this is the real
        // first-week-back case.
        let history = (0..<3).map { offset in
            let date = Self.asOf.adding(days: -offset)
            return Fix.rollup(date: date, loadAu: 6_000, workouts: [Fix.workout(on: date)])
        }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.spikeAfterLayoff)
        #expect(trend.acuteLoadAu == 18_000)
    }

    @Test("resuming after a week or more off warns, even with a base behind it")
    func spikeAfterLayoff() {
        // Week 1 trained, weeks 2 and 3 off entirely, week 4 trained again.
        var history = loadEveryDay(1_000, days: 28)
        history = history.filter { day in
            let back = day.date.days(until: Self.asOf)
            return back < 7 || back >= 21
        }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.layoffDays >= LoadThresholds.layoffDays)
        #expect(trend.spikeAfterLayoff)
    }

    @Test("a layoff with no return to training is not a spike")
    func layoffWithoutReturn() {
        var history = loadEveryDay(1_000, days: 28)
        history = history.filter { $0.date.days(until: Self.asOf) >= 10 }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.layoffDays >= LoadThresholds.layoffDays)
        #expect(trend.acuteLoadAu == 0)
        #expect(!trend.spikeAfterLayoff)
    }

    @Test("the longest layoff is measured, not the total days off")
    func longestLayoffRun() {
        // Trained on exactly two days, 10 days apart, inside the window.
        let history = [Self.asOf.adding(days: -14), Self.asOf.adding(days: -4)].map { date in
            Fix.rollup(date: date, loadAu: 5_000, workouts: [Fix.workout(on: date)])
        }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        // The longest gap is the 13 days before the first session, inside a 28-day window.
        #expect(trend.layoffDays == 13)
    }

    @Test("a day whose load could not be computed is counted, not zeroed")
    func unmeasuredDaysAreCounted() {
        var history = loadEveryDay(1_000, days: 28)
        // Three days kept their workout but lost their heart-rate data.
        let broken = [1, 2, 3].map { offset -> DayRollup in
            let date = Self.asOf.adding(days: -offset)
            return Fix.rollup(date: date, workouts: [Fix.workout(on: date, hrAvgBpm: nil)])
        }
        history = history.filter { day in !broken.contains { $0.date == day.date } } + broken

        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.unmeasuredDays == 3)
        // Those days add nothing to the totals, rather than adding zero and claiming to
        // know it.
        #expect(trend.acuteLoadAu == 4_000)
    }

    @Test("a rest day and a missing day are told apart")
    func restVersusMissing() {
        let date = Self.asOf
        #expect(LoadTrendEngine.dayLoad(nil) == .unmeasured)
        #expect(LoadTrendEngine.dayLoad(Fix.rollup(date: date)) == .rest)
        #expect(LoadTrendEngine.dayLoad(Fix.rollup(date: date, loadAu: 6_120))
            == .measured(6_120))
        #expect(LoadTrendEngine.dayLoad(Fix.rollup(date: date,
                                                   workouts: [Fix.workout(on: date)]))
            == .unmeasured)
    }

    @Test("days outside the chronic window do not count")
    func windowIsBounded() {
        var history = loadEveryDay(1_000, days: 28)
        history += (28..<60).map { offset in
            let date = Self.asOf.adding(days: -offset)
            return Fix.rollup(date: date, loadAu: 90_000, workouts: [Fix.workout(on: date)])
        }
        let trend = LoadTrendEngine.trend(history: history, asOf: Self.asOf)
        #expect(trend.chronicLoadAu == 7_000)
    }

    @Test("loadAu is read as stored, never recomputed here")
    func loadAuIsTheContractsNumber() {
        // The formula lives once, in `docs/EXPORT_SCHEMA.md` §1 and `TrainingRollup`.
        // A day whose stored load disagrees with its workouts is reported as stored.
        let date = Self.asOf
        let history = [Fix.rollup(date: date, loadAu: 42,
                                  workouts: [Fix.workout(on: date, durationMinutes: 999,
                                                          hrAvgBpm: 190)])]
        #expect(LoadTrendEngine.trend(history: history, asOf: date).acuteLoadAu == 42)
    }

    private func loadEveryDay(_ load: Double, days: Int) -> [DayRollup] {
        (0..<days).map { offset in
            let date = Self.asOf.adding(days: -offset)
            return Fix.rollup(date: date, loadAu: load, workouts: [Fix.workout(on: date)])
        }
    }
}
