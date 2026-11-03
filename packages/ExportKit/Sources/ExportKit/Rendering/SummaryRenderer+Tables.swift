import AscensionCore
import Foundation

extension SummaryRenderer {
    /// Current form: the last 7 days beside the whole 28, so a reader sees direction
    /// without being handed 28 rows of numbers to average itself.
    func averages() -> String {
        let month = SummaryWindow(rollups: snapshot.rollups)
        let week = month.lastSeven
        let rows = [
            metricRow("Calories kcal", week.meanKcal, month.meanKcal, places: 0),
            metricRow("Protein g", week.meanProteinG, month.meanProteinG, places: 0),
            metricRow("Steps", week.meanSteps, month.meanSteps, places: 0),
            sleepRow(week: week.meanSleepMinutes, month: month.meanSleepMinutes),
            metricRow("Weight kg", week.weightKg, month.weightKg, places: 1),
            metricRow("Sessions / week", week.sessionsPerWeek, month.sessionsPerWeek, places: 1)
        ]
        return """
        ## Averages

        | Metric | 7-day | 28-day |
        | --- | --- | --- |
        \(rows.joined(separator: "\n"))

        \(trendLine(month))

        """
    }

    /// The three body numbers a reader asks for first, on one line.
    private func trendLine(_ window: SummaryWindow) -> String {
        var parts: [String] = []
        if let latest = window.latestWeightKg {
            parts.append("\(Format.fixed(latest, places: 1)) kg")
        }
        if let average = window.latestWeightAvg7Kg {
            parts.append("7-day avg \(Format.fixed(average, places: 1)) kg")
        }
        if let rate = window.rateKgPerWeek {
            parts.append("\(Format.signed(rate, places: 1)) kg/week")
        }
        let goal = snapshot.documents.goalSettings.body.goalWeightKg
        parts.append("goal \(Format.fixed(goal, places: 1)) kg")
        return "- Trend: " + parts.joined(separator: " · ")
    }

    private func metricRow(_ name: String, _ week: Double?, _ month: Double?,
                           places: Int) -> String {
        "| \(name) | \(cell(week, places: places)) | \(cell(month, places: places)) |"
    }

    private func sleepRow(week: Double?, month: Double?) -> String {
        let render = { (value: Double?) -> String in
            value.map { Format.duration(minutes: Int($0.rounded())) } ?? "—"
        }
        return "| Sleep | \(render(week)) | \(render(month)) |"
    }

    private func cell(_ value: Double?, places: Int) -> String {
        guard let value else { return "—" }
        return places == 0 ? Format.groupedWhole(value) : Format.fixed(value, places: places)
    }

    /// Adherence over the window. The win counts come straight from the stored `wins`,
    /// never recomputed here, so the summary can never disagree with the consistency
    /// grid (`docs/EXPORT_SCHEMA.md` §1).
    func adherence() -> String {
        let window = SummaryWindow(rollups: snapshot.rollups)
        let targets = snapshot.documents.goalSettings.targets
        let total = window.dayCount
        let sleepTarget = Format.duration(minutes: targets.sleepMinutes)
        return """
        ## Adherence

        - Sessions: \(SummaryWindow.ratio(window.sessionsDone, of: window.sessionsPlanned,
                                          noun: "planned"))
        - Protein ≥ \(targets.proteinMinG) g: \
        \(SummaryWindow.ratio(window.winDays(\.protein), of: total))
        - Steps ≥ \(Format.grouped(targets.steps)): \
        \(SummaryWindow.ratio(window.winDays(\.steps), of: total))
        - Sleep ≥ \(sleepTarget): \(SummaryWindow.ratio(window.winDays(\.sleep), of: total))
        - All four wins: \(SummaryWindow.ratio(window.perfectDays, of: total))
        - Days with food logged: \(SummaryWindow.ratio(window.loggedDays, of: total))

        """
    }

    /// The last 14 days, one row each — the detail a reader needs to answer "how is it
    /// going" without opening `export.json`.
    func recentTable() -> String {
        let rows = SummaryWindow(rollups: snapshot.rollups).recent.map(recentRow)
        let body = rows.isEmpty ? ["| — | — | — | — | — | — | — | — | — | — |"] : rows
        return """
        ## Last 14 days

        | Date | Day | Readiness | Session | kcal | Protein g | Steps | Sleep | Weight kg | Wins |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        \(body.joined(separator: "\n"))

        """
    }

    private func recentRow(_ rollup: DayRollup) -> String {
        let missing = "—"
        var fields: [String] = [rollup.date.rawValue]
        fields.append(Format.weekday(rollup.date, in: environment) ?? missing)
        fields.append(rollup.readiness.map { String($0.score) } ?? missing)
        fields.append(sessionCell(rollup.training))
        fields.append(rollup.nutrition.kcal.map(Format.groupedWhole) ?? missing)
        fields.append(rollup.nutrition.proteinG.map(Format.groupedWhole) ?? missing)
        fields.append(rollup.activity.steps.map(Format.grouped) ?? missing)
        fields.append(rollup.sleep.asleepMinutes.map { Format.duration(minutes: $0) } ?? missing)
        fields.append(rollup.body.weightKg.map { Format.fixed($0, places: 1) } ?? missing)
        fields.append(String(rollup.wins.total))
        return "| " + fields.joined(separator: " | ") + " |"
    }

    /// What the day's training did against what it planned, in one cell.
    private func sessionCell(_ training: TrainingRollup) -> String {
        guard let planned = training.sessionPlanned else {
            return training.sessionDone ? "unplanned" : "—"
        }
        if planned == .rest { return training.sessionDone ? "rest, trained" : "rest" }
        return training.sessionDone ? planned.rawValue : "\(planned.rawValue), missed"
    }
}
