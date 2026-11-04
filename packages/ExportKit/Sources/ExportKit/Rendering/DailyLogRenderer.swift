import AscensionCore
import Foundation

/// One day of `daily-log.md`, in the shape spec §9.1 fixes.
///
/// Written for an AI reader: plain facts with units inline, one line per concern, no
/// prose and no encouragement. A line is omitted entirely when its data was not
/// measured — `null` means *not measured*, and a line of blanks would assert otherwise.
struct DailyLogRenderer {
    let environment: ExportEnvironment
    let snapshot: ExportSnapshot

    private var targets: GoalTargets { snapshot.documents.goalSettings.targets }

    /// The `## 2026-11-09 (Mon)` block for one day, newline-terminated.
    func block(for rollup: DayRollup) -> String {
        var lines = [header(rollup.date)]
        lines.append(contentsOf: readinessLine(rollup).map { [$0] } ?? [])
        lines.append(contentsOf: workoutLines(rollup))
        lines.append(contentsOf: topSetsLine(rollup).map { [$0] } ?? [])
        lines.append(contentsOf: foodLines(rollup))
        lines.append(contentsOf: sleepLine(rollup).map { [$0] } ?? [])
        lines.append(contentsOf: bodyLine(rollup).map { [$0] } ?? [])
        return lines.joined(separator: "\n") + "\n"
    }

    func header(_ date: CalendarDate) -> String {
        guard let weekday = Format.weekday(date, in: environment) else {
            return "## \(date.rawValue)"
        }
        return "## \(date.rawValue) (\(weekday))"
    }

    private func readinessLine(_ rollup: DayRollup) -> String? {
        guard let readiness = rollup.readiness else { return nil }
        var line = "- Readiness: \(readiness.score) — \(readiness.verdict.journalText)"
        if !readiness.reasons.isEmpty {
            line += " (\(readiness.reasons.joined(separator: "; ")))"
        }
        return line
    }

    private func workoutLines(_ rollup: DayRollup) -> [String] {
        let workouts = rollup.training.workouts
        guard !workouts.isEmpty else {
            guard let planned = rollup.training.sessionPlanned else { return [] }
            let note = planned == .rest ? "rest day" : "\(planned.rawValue) planned"
            return ["- Workout: none (\(note))"]
        }
        return workouts.map(workoutLine)
    }

    private func workoutLine(_ workout: WorkoutSummary) -> String {
        var parts = [workout.type.workoutTypeLabel]
        if let start = Format.clockTime(workout.startedAt, in: environment),
           let end = Format.clockTime(workout.endedAt, in: environment) {
            parts.append("\(start)\u{2013}\(end)")
        }
        parts.append("\(workout.durationMinutes) min")
        if let kcal = workout.activeEnergyKcal {
            parts.append("\(Format.groupedWhole(kcal)) kcal")
        }
        if let average = workout.hrAvgBpm, let maximum = workout.hrMaxBpm {
            parts.append("HR \(average) avg / \(maximum) max")
        } else if let average = workout.hrAvgBpm {
            parts.append("HR \(average) avg")
        }
        return "- Workout (\(workout.source)): " + parts.joined(separator: ", ")
    }

    private func topSetsLine(_ rollup: DayRollup) -> String? {
        let sets = rollup.training.topSets
        guard !sets.isEmpty else { return nil }
        let rendered = sets.map { set in
            let name = snapshot.exerciseName(set.exerciseId)
            return "\(name) \(Format.decimal(set.weightKg, places: 1)) kg \u{00D7} \(set.reps)"
        }
        return "- Top sets: " + rendered.joined(separator: " \u{00B7} ")
    }

    private func foodLines(_ rollup: DayRollup) -> [String] {
        let nutrition = rollup.nutrition
        var parts: [String] = []
        if let kcal = nutrition.kcal { parts.append("\(Format.groupedWhole(kcal)) kcal") }
        if let protein = nutrition.proteinG {
            parts.append("protein \(Format.groupedWhole(protein)) g / \(targets.proteinG) g")
        }
        if let fat = nutrition.fatG { parts.append("fat \(Format.groupedWhole(fat)) g") }
        if let carbs = nutrition.carbsG { parts.append("carbs \(Format.groupedWhole(carbs)) g") }
        // Water is in `export.json` and `rollups.csv`, not here: the spec §9.1 Food
        // line is calories and the three macros, and a fifth figure would push it past
        // a glance.
        let meals = mealLines(on: rollup.date)
        guard !parts.isEmpty else { return meals }
        return ["- Food: " + parts.joined(separator: " \u{00B7} ")] + meals
    }

    /// One indented line per meal slot, items joined so the portion stays attached to
    /// the food it belongs to.
    private func mealLines(on date: CalendarDate) -> [String] {
        let entries = snapshot.meals(on: date)
        guard !entries.isEmpty else { return [] }
        return MealKind.allCases
            .sorted { MealKind.exportOrder($0) < MealKind.exportOrder($1) }
            .compactMap { meal -> String? in
                let items = entries.filter { $0.meal == meal }
                guard !items.isEmpty else { return nil }
                let named = items.map { item in
                    "\(item.name) \(Format.groupedWhole(item.grams)) g"
                }
                let kcal = items.reduce(0) { $0 + $1.kcal }
                let protein = items.reduce(0) { $0 + $1.proteinG }
                return "  - \(meal.journalText): \(named.joined(separator: " + ")) "
                    + "\u{2014} \(Format.groupedWhole(kcal)) kcal, "
                    + "\(Format.groupedWhole(protein)) g protein"
            }
    }

    private func sleepLine(_ rollup: DayRollup) -> String? {
        var parts: [String] = []
        if let asleep = rollup.sleep.asleepMinutes {
            parts.append(Format.duration(minutes: asleep))
        }
        if let resting = rollup.vitals.restingHrBpm { parts.append("resting HR \(resting)") }
        if let hrv = rollup.vitals.hrvSdnnMs {
            parts.append("HRV \(Format.decimal(hrv, places: 1)) ms")
        }
        guard !parts.isEmpty else { return nil }
        return "- Sleep (last night): " + parts.joined(separator: ", ")
    }

    private func bodyLine(_ rollup: DayRollup) -> String? {
        var parts: [String] = []
        if let weight = rollup.body.weightKg {
            var text = "Weight: \(Format.fixed(weight, places: 1)) kg"
            var trend: [String] = []
            if let average = rollup.body.weightAvg7Kg {
                trend.append("7-day avg \(Format.fixed(average, places: 1))")
            }
            if let rate = rollup.body.rateKgPerWeek {
                trend.append("\(Format.signed(rate, places: 1)) kg/week")
            }
            if !trend.isEmpty { text += " (\(trend.joined(separator: ", ")))" }
            parts.append(text)
        }
        if let steps = rollup.activity.steps { parts.append("Steps: \(Format.grouped(steps))") }
        guard !parts.isEmpty else { return nil }
        return "- " + parts.joined(separator: " \u{00B7} ")
    }
}
