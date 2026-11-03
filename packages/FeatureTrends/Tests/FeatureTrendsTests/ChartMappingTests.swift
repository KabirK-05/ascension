import AscensionCore
import AscensionEngines
import DesignSystem
import Foundation
import Testing

@testable import FeatureTrends

/// Chart data mapping: the presenter copies the engine's numbers and never recomputes
/// one (spec §8).
struct ChartMappingTests {

    static let snapshot = TrendsFixtures.cutting
    static var report: TrendsReport { snapshot.report }
    static var presentation: TrendsPresentation { TrendsPresenter.present(snapshot) }

    @Test("every weigh-in the engine reports becomes a point, and no extra one appears")
    func weightPointsMatchTheEngine() {
        #expect(Self.presentation.weight.points.count == Self.report.weight.points.count)
        #expect(Self.presentation.weight.average.count
            == Self.report.weight.rollingAverage.count)
    }

    @Test("a point's value is the engine's value, unrounded and unscaled")
    func pointValuesAreTheEngineValues() {
        let engine = Self.report.weight.rollingAverage.map(\.value)
        let drawn = Self.presentation.weight.average.map(\.value)
        #expect(engine == drawn)
    }

    @Test("points are dated in the user's own timezone, on the day the contract keyed")
    func pointsLandOnTheirOwnDay() {
        let calendar = TrendsPresenter.calendar(timezone: Seed.timezone)
        for (value, point) in zip(Self.report.weight.points.map(\.date),
                                  Self.presentation.weight.points) {
            let components = calendar.dateComponents([.year, .month, .day], from: point.date)
            #expect(components.year == value.year)
            #expect(components.month == value.month)
            #expect(components.day == value.day)
        }
    }

    @Test("a day sits at noon, so no DST shift can slide it into its neighbour")
    func pointsSitAtNoon() {
        let calendar = TrendsPresenter.calendar(timezone: Seed.timezone)
        // 2026-11-01 is the North American DST fall-back.
        guard let date = TrendsPresenter.date(of: CalendarDate.literal("2026-11-01"),
                                              in: calendar) else {
            Issue.record("expected a date")
            return
        }
        #expect(calendar.component(.day, from: date) == 1)
        #expect(calendar.component(.hour, from: date) == 12)
    }

    @Test("the rate and the goal distance are the engine's, as written")
    func weightHeaderReadsTheEngine() {
        let panel = Self.presentation.weight
        let trend = Self.report.weight
        #expect(panel.rate == TrendsFormat.signedDecimal(trend.rateKgPerWeek ?? 0))
        #expect(panel.toGoal == TrendsFormat.optional(trend.kgToGoal))
    }

    @Test("weekly load bars are the engine's weekly totals")
    func loadBarsMatchTheEngine() {
        #expect(Self.presentation.load.weekly.map(\.value)
            == Self.report.load.weeklyLoadAu.map(\.value))
    }

    @Test("the band shown is the band the engine computed, never one derived here")
    func bandIsTheEngineBand() {
        #expect(Self.presentation.load.band == Self.report.load.band)
    }

    @Test("a layoff shows the spike the engine warns about")
    func layoffShowsTheSpike() {
        let snapshot = TrendsFixtures.layoff
        let panel = TrendsPresenter.present(snapshot).load
        #expect(panel.spikeAfterLayoff == snapshot.report.load.spikeAfterLayoff)
        #expect(panel.layoffDays == snapshot.report.load.layoffDays)
    }

    @Test("hit-rate and adherence are the engine's percentages")
    func habitsReadTheEngine() {
        let panel = Self.presentation.habits
        let habits = Self.report.habits
        #expect(panel.proteinHitRate == TrendsFormat.percent(habits.proteinHitRatePct))
        #expect(panel.proteinHitDays == habits.proteinHitDays)
        #expect(panel.completedSessions == habits.completedSessions)
        #expect(panel.plannedSessions == habits.plannedSessions)
    }

    @Test("a series with no measurements is dropped, not drawn as an empty axis")
    func emptySeriesAreDropped() {
        let empty = TrendsFixtures.snapshot(asOf: TrendsFixtures.saturday,
                                            shape: TrendsFixtures.Shape(days: 1))
        let labels = TrendsPresenter.present(empty).series.map(\.label)
        let vitals = empty.report.habits
        #expect(labels.contains("VO₂ max") == !vitals.vo2MaxSeries.isEmpty)
        #expect(labels.contains("Resting HR") == !vitals.restingHrSeries.isEmpty)
    }

    @Test("a first launch draws no points and invents no numbers")
    func firstLaunchDrawsNothing() async throws {
        let snapshot = try await DefaultTrendsDataSource(timezone: Seed.timezone).snapshot()
        let presentation = TrendsPresenter.present(snapshot)

        #expect(presentation.weight.points.isEmpty)
        #expect(presentation.weight.average.isEmpty)
        #expect(presentation.weight.latestAverage == TrendsFormat.unmeasured)
        #expect(presentation.weight.rate == TrendsFormat.unmeasured)
        #expect(presentation.suggestion == nil)
        #expect(presentation.series.isEmpty)
    }

    @Test("every chart carries a description for VoiceOver")
    func chartsAreDescribed() {
        let presentation = Self.presentation
        #expect(!presentation.weight.chartDescription.isEmpty)
        #expect(!presentation.load.chartDescription.isEmpty)
        for series in presentation.series {
            #expect(!series.chartDescription.isEmpty)
        }
    }

    @Test("the review card only exists on the day it covers")
    func reviewOnlyExistsOnSunday() {
        #expect(WeeklyReview.isDue(TrendsFixtures.sunday))
        #expect(!WeeklyReview.isDue(TrendsFixtures.saturday))
    }

    @Test("the review's rows are the facts, not a second reading of the history")
    func reviewRowsReadTheFacts() {
        let snapshot = TrendsFixtures.sundayReview
        let facts = WeeklyReviewFacts(report: snapshot.weeklyReport, goals: snapshot.goals)
        let rows = TrendsPresenter.reviewRows(facts)

        #expect(rows.first?.label == "Sessions")
        #expect(rows.first?.value
            == "\(facts.sessionsCompleted)/\(facts.sessionsPlanned)")
        #expect(rows.contains { $0.label == "Protein" })
    }
}

/// `docs/DESIGN_RULES.md` §1.3, checked against every label this package generates.
///
/// `DesignSystem` asserts the same rule at each call site in debug builds, which is what
/// caught `Acute:chronic`. This catches the dynamic ones — the series and review rows —
/// without having to render a view first.
struct LabelComplianceTests {

    @Test("every generated series label is a noun of at most two words")
    func seriesLabelsAreLabels() {
        for snapshot in [TrendsFixtures.cutting, TrendsFixtures.sundayReview] {
            for series in TrendsPresenter.present(snapshot).series {
                #expect(LabelRule.isCompliant(series.label), "\(series.label)")
            }
        }
    }

    @Test("every review row label is a noun of at most two words")
    func reviewRowLabelsAreLabels() {
        let snapshot = TrendsFixtures.sundayReview
        let facts = WeeklyReviewFacts(report: snapshot.weeklyReport, goals: snapshot.goals)
        for row in TrendsPresenter.reviewRows(facts) {
            #expect(LabelRule.isCompliant(row.label), "\(row.label)")
        }
    }

    @Test("a band name is a word, not a sentence")
    func bandNamesAreLabels() {
        for band in AcwrBand.allCases {
            #expect(LabelRule.isCompliant(TrendsPresenter.name(of: band)))
        }
    }
}
