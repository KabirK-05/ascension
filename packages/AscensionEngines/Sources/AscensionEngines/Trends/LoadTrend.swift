import AscensionCore
import Foundation

/// Where an acute:chronic workload ratio sits.
public enum AcwrBand: String, Codable, Hashable, Sendable, CaseIterable {
    /// Training less than the body is used to.
    case detraining

    /// The band to live in.
    case optimal

    /// Ramping faster than is comfortable.
    case caution

    /// A spike.
    case highRisk
}

/// What a single day contributed to training load.
enum DayLoad: Hashable, Sendable {
    /// `loadAu` was computable.
    case measured(Double)

    /// No workout landed, so the load really was zero.
    case rest

    /// A workout landed but its load could not be computed — missing heart rate, say —
    /// or the day is not in the history at all. Never counted as zero.
    case unmeasured
}

/// Training load over time (spec §F6).
public struct LoadTrend: Hashable, Sendable {
    /// One total per week, each dated by the day its week ends on, most recent last.
    public let weeklyLoadAu: [DatedValue]

    /// Load over the last ``LoadThresholds/acuteWindowDays`` days.
    public let acuteLoadAu: Double

    /// Mean weekly load across the last ``LoadThresholds/chronicWindowDays`` days.
    public let chronicLoadAu: Double

    /// `acute / chronic`. `nil` when there is no chronic load to divide by, which is the
    /// case on a fresh install and after a long layoff.
    public let acuteChronicRatio: Double?

    public let band: AcwrBand?

    /// Days in the chronic window whose load could not be computed. The ratio is still
    /// reported; this is how far to trust it.
    public let unmeasuredDays: Int

    /// The longest run of consecutive days with no recorded workout, inside the chronic
    /// window.
    public let layoffDays: Int

    /// Spec §F6: "spike warning after layoffs". True when training has resumed on top of
    /// a week or more off, or on top of no chronic load at all.
    public let spikeAfterLayoff: Bool

    public let asOf: CalendarDate
}

/// Every number the load rules turn on.
public enum LoadThresholds {
    public static let acuteWindowDays = 7
    public static let chronicWindowDays = 28

    /// Below this ratio, `detraining`.
    public static let detrainingBelow: Double = 0.8

    /// Below this ratio, `optimal`.
    public static let optimalBelow: Double = 1.3

    /// Below this ratio, `caution`; at or above it, `highRisk`.
    public static let cautionBelow: Double = 1.5

    /// Consecutive days with no recorded workout that count as a layoff.
    public static let layoffDays = 7
}

/// Load, acute:chronic ratio and deload-adjacent warnings (spec §F6).
///
/// `loadAu` is **not** recomputed here. It is defined once in the contract
/// (`docs/EXPORT_SCHEMA.md` §1, implemented as `TrainingRollup.loadAu`) and read as
/// stored, so the app, the Worker and this engine can never disagree about it.
public enum LoadTrendEngine {
    public static func trend(history: [DayRollup], asOf: CalendarDate) -> LoadTrend {
        let byDate = Dictionary(history.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let chronicWindow = asOf.trailingWindow(days: LoadThresholds.chronicWindowDays)
        let loads = chronicWindow.map { date in dayLoad(byDate[date]) }

        let acute = total(of: loads.suffix(LoadThresholds.acuteWindowDays))
        let weeks = Double(LoadThresholds.chronicWindowDays) / Double(LoadThresholds.acuteWindowDays)
        let chronic = total(of: loads) / weeks
        let ratio = chronic > 0 ? acute / chronic : nil
        let layoff = longestLayoff(dates: chronicWindow, byDate: byDate)

        return LoadTrend(
            weeklyLoadAu: weeklySeries(dates: chronicWindow, loads: loads),
            acuteLoadAu: acute,
            chronicLoadAu: chronic,
            acuteChronicRatio: ratio,
            band: ratio.map(band(for:)),
            unmeasuredDays: loads.count { $0 == .unmeasured },
            layoffDays: layoff,
            spikeAfterLayoff: acute > 0 && (chronic <= 0 || layoff >= LoadThresholds.layoffDays),
            asOf: asOf)
    }

    public static func band(for ratio: Double) -> AcwrBand {
        if ratio < LoadThresholds.detrainingBelow { return .detraining }
        if ratio < LoadThresholds.optimalBelow { return .optimal }
        if ratio < LoadThresholds.cautionBelow { return .caution }
        return .highRisk
    }

    /// A day's load, keeping *no workout* and *not measured* apart.
    static func dayLoad(_ day: DayRollup?) -> DayLoad {
        guard let day else { return .unmeasured }
        if let load = day.training.loadAu { return .measured(load) }
        return day.training.workouts.isEmpty ? .rest : .unmeasured
    }

    /// Only measured load counts. An unmeasured day adds nothing rather than adding zero,
    /// and is reported separately so the ratio is never read as more certain than it is.
    private static func total(of loads: some Sequence<DayLoad>) -> Double {
        loads.reduce(0.0) { running, load in
            switch load {
            case .measured(let value): return running + value
            case .rest, .unmeasured: return running
            }
        }
    }

    /// Weekly totals over the chronic window, oldest week first.
    private static func weeklySeries(dates: [CalendarDate], loads: [DayLoad]) -> [DatedValue] {
        let perWeek = LoadThresholds.acuteWindowDays
        guard dates.count == loads.count, perWeek > 0 else { return [] }
        return stride(from: 0, to: dates.count, by: perWeek).compactMap { start in
            let end = min(start + perWeek, dates.count)
            guard let weekEnding = dates[start..<end].last else { return nil }
            return DatedValue(date: weekEnding, value: total(of: loads[start..<end]))
        }
    }

    /// The longest run of consecutive days with no recorded workout.
    ///
    /// A day missing from the history has no recorded workout and so extends the run: a
    /// gap in the data looks like time off, which is the reading that warns rather than
    /// the one that stays quiet.
    private static func longestLayoff(dates: [CalendarDate],
                                      byDate: [CalendarDate: DayRollup]) -> Int {
        var longest = 0
        var run = 0
        for date in dates {
            let trained = byDate[date].map { !$0.training.workouts.isEmpty } ?? false
            run = trained ? 0 : run + 1
            longest = max(longest, run)
        }
        return longest
    }
}
