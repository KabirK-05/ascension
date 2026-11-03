import AscensionCore
import AscensionEngines
import Foundation
import HealthBridge
import SyncClient

/// Assembles one day's `DayRollup` from HealthKit's half and the device's half.
///
/// Pure, and deliberately thin: both halves are already defined elsewhere and this only
/// puts them in the right order. `HealthBridge`'s `snapshot.applied(to:)` writes activity,
/// sleep, vitals, body, mirrored water, workouts and `loadAu`; `SyncClient`'s
/// `RollupAssembler` overlays meals, the plan, top sets, check-in, readiness and the
/// trends, and computes `wins` through `AscensionCore.WinsCalculator`. Nothing here
/// recomputes either half — a second implementation of `wins` or `loadAu` is exactly how
/// the grid and the export would come to disagree.
enum RollupBuilder {
    static func rollup(snapshot: DayHealthSnapshot,
                       device: DeviceDay,
                       goals: GoalSettingsDocument,
                       timeZone: TimeZone,
                       clock: some SyncClock) -> DayRollup {
        let empty = RollupAssembler.empty(date: snapshot.date, goals: goals, clock: clock)
        let measured = snapshot.applied(to: empty, timeZone: timeZone)
        return RollupAssembler.assemble(measured: measured, device: device,
                                        goals: goals, clock: clock)
    }

    /// The rolling numbers `HealthBridge` declines to derive and `SyncClient` cannot.
    ///
    /// `weightAvg7Kg` and `rateKgPerWeek` come from `WeightTrendEngine`, so the figure the
    /// Trends tab shows and the figure the Worker stores are the same function of the same
    /// history.
    ///
    /// `consistencySd7Minutes` is left `nil` on purpose. No engine computes it — spec §F5
    /// scores it and `HabitTrendsEngine` only reads it back off the rollups — and deriving
    /// a 7-day deviation here would put a trend calculation in the app shell, outside the
    /// package the spec calls the product (§8). Readiness drops the term and reports lower
    /// coverage, which is the honest answer while nothing measures it.
    static func trends(history: [DayRollup],
                       goals: GoalSettingsDocument,
                       asOf: CalendarDate) -> TrendOverlay {
        let weight = WeightTrendEngine.trend(history: history, goals: goals, asOf: asOf)
        return TrendOverlay(weightAvg7Kg: weight.latestAverageKg,
                            rateKgPerWeek: weight.rateKgPerWeek,
                            consistencySd7Minutes: nil)
    }

    /// Today's readiness, scored from the history the ledger holds.
    ///
    /// Only ever computed for the day being lived. A past day keeps the verdict it was
    /// given at the time — rescoring Tuesday on Friday against Friday's baselines would
    /// rewrite history, and the verdict is a morning decision, not a property of the data.
    static func readiness(history: [DayRollup],
                          clock: EngineClock,
                          program: ProgramDocument,
                          goals: GoalSettingsDocument) -> ReadinessRollup {
        let input = ReadinessHistory.input(history: history, clock: clock,
                                           program: program, goals: goals)
        return ReadinessEngine.assess(input).rollup
    }
}
