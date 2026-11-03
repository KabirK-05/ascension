import AscensionCore
import AscensionEngines
import Foundation

/// A ``TrendsReport``, turned into the exact strings and points the cards draw.
///
/// Pure and synchronous, so every mapping on this tab is testable without SwiftUI and
/// without a clock. **No arithmetic on measurements happens here** beyond converting a
/// `CalendarDate` to a `Date` for a chart axis: the averages, the rate, the ratio, the
/// hit-rate and the thresholds are all the engine's, read as published (spec §8).
public enum TrendsPresenter {

    public static func present(_ snapshot: TrendsSnapshot,
                               review: WeeklyReviewText? = nil) -> TrendsPresentation {
        let report = snapshot.report
        let calendar = calendar(timezone: snapshot.clock.timezone)
        return TrendsPresentation(
            weight: weight(report.weight, calendar: calendar),
            suggestion: report.calorieSuggestion.map(suggestion),
            load: load(report.load, deload: report.deload, calendar: calendar),
            habits: habits(report.habits),
            series: series(report.habits, calendar: calendar),
            review: reviewPanel(report: snapshot.weeklyReport, goals: snapshot.goals,
                                text: review))
    }

    // MARK: - Dates

    /// The calendar a chart axis is laid out in: the user's own, so a point lands on the
    /// day the contract keyed it to.
    static func calendar(timezone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    /// Noon, so a day's point cannot slide into its neighbour under a DST shift.
    static func date(of day: CalendarDate, in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: day.year, month: day.month,
                                           day: day.day, hour: 12))
    }

    static func points(_ series: [DatedValue], calendar: Calendar) -> [ChartPoint] {
        series.compactMap { value in
            date(of: value.date, in: calendar).map { ChartPoint(date: $0, value: value.value) }
        }
    }

    // MARK: - Weight

    static func weight(_ trend: WeightTrend, calendar: Calendar) -> WeightPanel {
        let average = trend.latestAverageKg
        return WeightPanel(
            points: points(trend.points, calendar: calendar),
            average: points(trend.rollingAverage, calendar: calendar),
            latestAverage: TrendsFormat.optional(average),
            spokenLatestAverage: average.map { "\(TrendsFormat.decimal($0)) kilograms" }
                ?? TrendsFormat.spokenUnmeasured,
            rate: trend.rateKgPerWeek.map { TrendsFormat.signedDecimal($0) }
                ?? TrendsFormat.unmeasured,
            spokenRate: trend.rateKgPerWeek.map {
                TrendsFormat.spokenSignedDecimal($0, unit: "kilograms per week")
            } ?? TrendsFormat.spokenUnmeasured,
            toGoal: TrendsFormat.optional(trend.kgToGoal),
            spokenToGoal: trend.kgToGoal.map { "\(TrendsFormat.decimal($0)) kilograms to go" }
                ?? TrendsFormat.spokenUnmeasured,
            chartDescription: weightDescription(trend))
    }

    /// What VoiceOver reads in place of the chart (§4.3). A chart with no accessible
    /// representation is unusable, so this states the shape in words: how many days, what
    /// the average is now, and which way it is moving.
    static func weightDescription(_ trend: WeightTrend) -> String {
        guard let average = trend.latestAverageKg else {
            return "Weight, no 7-day average yet"
        }
        var sentence = "Weight over \(trend.points.count) days, "
            + "7-day average \(TrendsFormat.decimal(average)) kilograms"
        if let rate = trend.rateKgPerWeek {
            sentence += ", \(TrendsFormat.spokenSignedDecimal(rate, unit: "kilograms per week"))"
        }
        return sentence
    }

    // MARK: - Calorie suggestion

    static func suggestion(_ suggestion: CalorieSuggestion) -> SuggestionPanel {
        SuggestionPanel(id: suggestion.id,
                        suggestedKcal: suggestion.suggestedKcal,
                        currentKcal: suggestion.currentKcal,
                        reason: suggestion.reason)
    }

    // MARK: - Load

    static func load(_ trend: LoadTrend, deload: DeloadStatus, calendar: Calendar) -> LoadPanel {
        LoadPanel(
            weekly: points(trend.weeklyLoadAu, calendar: calendar),
            ratio: trend.acuteChronicRatio.map { TrendsFormat.decimal($0, places: 2) }
                ?? TrendsFormat.unmeasured,
            spokenRatio: trend.acuteChronicRatio.map {
                "Acute to chronic ratio \(TrendsFormat.decimal($0, places: 2))"
            } ?? TrendsFormat.spokenUnmeasured,
            band: trend.band,
            bandName: trend.band.map(name(of:)) ?? TrendsFormat.unmeasured,
            spikeAfterLayoff: trend.spikeAfterLayoff,
            layoffDays: trend.layoffDays,
            deloadWeek: deload.shouldPrompt ? deload.weeksIntoBlock : nil,
            unmeasuredDays: trend.unmeasuredDays,
            chartDescription: loadDescription(trend))
    }

    /// The band as a noun (§1.3). The engine's case names are the status; this is how
    /// they are written down.
    static func name(of band: AcwrBand) -> String {
        switch band {
        case .detraining: return "Detraining"
        case .optimal: return "Optimal"
        case .caution: return "Caution"
        case .highRisk: return "High"
        }
    }

    static func loadDescription(_ trend: LoadTrend) -> String {
        guard let ratio = trend.acuteChronicRatio, let band = trend.band else {
            return "Training load, no chronic load to compare against"
        }
        var sentence = "Training load over \(trend.weeklyLoadAu.count) weeks, "
            + "acute to chronic ratio \(TrendsFormat.decimal(ratio, places: 2)), "
            + "\(name(of: band).lowercased())"
        if trend.spikeAfterLayoff {
            sentence += ", spike after \(trend.layoffDays) days off"
        }
        return sentence
    }

    // MARK: - Habits

    static func habits(_ trends: HabitTrends) -> HabitsPanel {
        HabitsPanel(proteinHitRate: TrendsFormat.percent(trends.proteinHitRatePct),
                    proteinHitDays: trends.proteinHitDays,
                    windowDays: trends.windowDays,
                    adherence: trends.adherencePct.map(TrendsFormat.percent)
                        ?? TrendsFormat.unmeasured,
                    completedSessions: trends.completedSessions,
                    plannedSessions: trends.plannedSessions)
    }

    // MARK: - Vitals and sleep

    /// VO2 max, resting HR and sleep duration (spec §F6).
    ///
    /// A series with nothing in it is dropped rather than drawn empty: §2.1 says an
    /// element the screen works without does not ship, and an axis with no line under it
    /// is exactly that.
    static func series(_ trends: HabitTrends, calendar: Calendar) -> [SeriesPanel] {
        let vo2 = SeriesStyle(label: "VO₂ max", unit: nil,
                              format: { TrendsFormat.decimal($0) },
                              spoken: { "VO2 max \(TrendsFormat.decimal($0))" })
        let restingHr = SeriesStyle(label: "Resting HR", unit: "bpm",
                                    format: { TrendsFormat.count($0) },
                                    spoken: { "\(TrendsFormat.count($0)) beats per minute" })
        let sleep = SeriesStyle(
            label: "Sleep", unit: nil,
            format: { TrendsFormat.duration(minutes: Int($0.rounded())) },
            spoken: { TrendsFormat.spokenDuration(minutes: Int($0.rounded())) })

        return [
            panel(vo2, series: trends.vo2MaxSeries, calendar: calendar),
            panel(restingHr, series: trends.restingHrSeries, calendar: calendar),
            panel(sleep, series: trends.sleepMinutesSeries, calendar: calendar)
        ].compactMap { $0 }
    }

    /// How one series is written down: the label it sits under, the unit beside its
    /// value, and the two ways its latest value is said — on screen and to VoiceOver.
    struct SeriesStyle {
        let label: String
        let unit: String?
        let format: (Double) -> String
        let spoken: (Double) -> String
    }

    private static func panel(_ style: SeriesStyle,
                              series: [DatedValue],
                              calendar: Calendar) -> SeriesPanel? {
        guard let latest = series.max(by: { $0.date < $1.date }) else { return nil }
        let mapped = points(series, calendar: calendar)
        guard !mapped.isEmpty else { return nil }
        return SeriesPanel(label: style.label,
                           latest: style.format(latest.value),
                           unit: style.unit,
                           spokenLatest: style.spoken(latest.value),
                           points: mapped,
                           chartDescription: "\(style.label) over \(mapped.count) days, "
                               + "latest \(style.spoken(latest.value))")
    }

    // MARK: - Weekly review

    static func reviewPanel(report: TrendsReport,
                            goals: GoalSettingsDocument,
                            text: WeeklyReviewText?) -> ReviewPanel? {
        guard let text else { return nil }
        let facts = WeeklyReviewFacts(report: report, goals: goals)
        return ReviewPanel(facts: facts, rows: reviewRows(facts), text: text)
    }

    /// The four measured facts §F7 asks for, in the order it lists them. A fact with no
    /// measurement behind it is left out rather than printed as a zero.
    static func reviewRows(_ facts: WeeklyReviewFacts) -> [ReviewRow] {
        var rows = [
            ReviewRow(label: "Sessions",
                      value: "\(facts.sessionsCompleted)/\(facts.sessionsPlanned)",
                      unit: nil,
                      spokenValue: "\(facts.sessionsCompleted) of \(facts.sessionsPlanned) done"),
            ReviewRow(label: "Protein",
                      value: TrendsFormat.percent(facts.proteinHitRatePct),
                      unit: nil,
                      spokenValue: "\(TrendsFormat.percent(facts.proteinHitRatePct)) of days "
                          + "at or over \(facts.proteinFloorG) grams")
        ]
        if let rate = facts.weightRateKgPerWeek {
            rows.append(ReviewRow(label: "Weight",
                                  value: TrendsFormat.signedDecimal(rate),
                                  unit: "kg/wk",
                                  spokenValue: TrendsFormat.spokenSignedDecimal(
                                      rate, unit: "kilograms per week")))
        }
        if let minutes = facts.sleepMeanMinutes {
            let rounded = Int(minutes.rounded())
            rows.append(ReviewRow(label: "Sleep",
                                  value: TrendsFormat.duration(minutes: rounded),
                                  unit: nil,
                                  spokenValue: TrendsFormat.spokenDuration(minutes: rounded)))
        }
        return rows
    }
}
