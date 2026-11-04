import AscensionCore
import Foundation

/// The rolling window `summary-latest.md` reports on, and the arithmetic over it.
///
/// Averages skip unmeasured days rather than treating them as zero: `null` means *not
/// measured*, so averaging it in as 0 would report a fast the user never had. Adherence
/// counts, by contrast, are over the whole window — a day with no protein logged is a
/// day the protein target was not met, which is what `wins` already says.
struct SummaryWindow {
    static let days = 28
    static let tableDays = 14

    let rollups: [DayRollup]

    init(rollups: [DayRollup], days: Int = SummaryWindow.days) {
        self.rollups = rollups.suffix(days)
    }

    var dayCount: Int { rollups.count }
    var firstDate: CalendarDate? { rollups.first?.date }
    var lastDate: CalendarDate? { rollups.last?.date }
    var recent: [DayRollup] { Array(rollups.suffix(Self.tableDays)) }
    var lastSeven: SummaryWindow { SummaryWindow(rollups: rollups, days: 7) }

    private func mean(_ value: (DayRollup) -> Double?) -> Double? {
        let measured = rollups.compactMap(value)
        guard !measured.isEmpty else { return nil }
        return measured.reduce(0, +) / Double(measured.count)
    }

    var meanKcal: Double? { mean { $0.nutrition.kcal } }
    var meanProteinG: Double? { mean { $0.nutrition.proteinG } }
    var meanSteps: Double? { mean { $0.activity.steps.map(Double.init) } }
    var meanSleepMinutes: Double? { mean { $0.sleep.asleepMinutes.map(Double.init) } }

    /// The mean measured weight over the window.
    ///
    /// A mean rather than the latest 7-day average, so the 7-day and 28-day columns are
    /// the same statistic over different spans and the comparison between them means
    /// something. The stored 7-day average — the number that matters (§F6) — is
    /// reported on its own line as `latestWeightAvg7Kg`.
    var weightKg: Double? { mean { $0.body.weightKg } }

    /// The most recent measured weight, 7-day average and rate of change.
    var latestWeightKg: Double? { rollups.reversed().compactMap { $0.body.weightKg }.first }

    var latestWeightAvg7Kg: Double? {
        rollups.reversed().compactMap { $0.body.weightAvg7Kg }.first
    }

    var rateKgPerWeek: Double? {
        rollups.reversed().compactMap { $0.body.rateKgPerWeek }.first
    }

    var sessionsDone: Int { rollups.count { $0.training.sessionDone } }

    /// Days the program prescribed a training session, rest days excluded.
    var sessionsPlanned: Int {
        rollups.count { rollup in
            guard let planned = rollup.training.sessionPlanned else { return false }
            return planned.isTrainingDay
        }
    }

    var sessionsPerWeek: Double? {
        guard dayCount > 0 else { return nil }
        return Double(sessionsDone) / Double(dayCount) * 7
    }

    func winDays(_ win: (Wins) -> Bool) -> Int { rollups.count { win($0.wins) } }

    var perfectDays: Int { rollups.count { $0.wins.total == Wins.totalRange.upperBound } }

    /// Days that carry any logged nutrition at all — the honest denominator for how
    /// much of the window the user actually recorded.
    var loggedDays: Int { rollups.count { $0.nutrition.kcal != nil } }
}

extension SummaryWindow {
    /// `18 of 28 (64%)`, or `18 of 22 planned (82%)` when the denominator needs
    /// naming. `—` when there is nothing to divide by.
    static func ratio(_ count: Int, of total: Int, noun: String? = nil) -> String {
        guard total > 0 else { return "—" }
        let percent = Int((Double(count) / Double(total) * 100).rounded())
        let denominator = noun.map { "\(total) \($0)" } ?? "\(total)"
        return "\(count) of \(denominator) (\(percent)%)"
    }
}
