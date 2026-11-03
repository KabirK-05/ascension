import AscensionCore
import Foundation

/// Assembles the `DayRollup` that goes up the wire (`docs/EXPORT_SCHEMA.md` §1).
///
/// Pure: the same measured half, the same device half and the same clock always give the
/// same rollup, byte for byte. Nothing here reads `Date()` or HealthKit.
///
/// `wins` comes from `AscensionCore.WinsCalculator` and is never computed here. The
/// contract says the device computes it once and the Worker stores what it was sent, so a
/// second implementation is the one way the grid could disagree with itself.
public enum RollupAssembler {
    /// Overlays the device's half onto `measured` — the rollup `HealthBridge` has already
    /// filled — and stamps `updatedAt` from the clock.
    ///
    /// - Parameters:
    ///   - measured: HealthKit's half: activity, sleep, vitals, body, workouts, `loadAu`
    ///     and mirrored water. Carries the day's `date`.
    ///   - device: meals, plan, top sets, check-in, readiness and the engines' trends.
    ///   - goals: the `goalSettings` targets `wins` is judged against.
    public static func assemble(measured: DayRollup,
                                device: DeviceDay,
                                goals: GoalSettingsDocument,
                                clock: some SyncClock) -> DayRollup {
        var rollup = measured
        rollup.timezone = goals.timezone
        rollup.updatedAt = clock.timestamp
        rollup.nutrition = merged(measuredWater: measured.nutrition.waterMl,
                                  logged: device.nutritionTotals)
        rollup.sleep.consistencySd7Minutes = device.trends.consistencySd7Minutes
            ?? measured.sleep.consistencySd7Minutes
        rollup.body.weightAvg7Kg = device.trends.weightAvg7Kg ?? measured.body.weightAvg7Kg
        rollup.body.rateKgPerWeek = device.trends.rateKgPerWeek ?? measured.body.rateKgPerWeek
        rollup.training.sessionPlanned = device.sessionPlanned
        rollup.training.sessionDone = device.sessionDone
        rollup.training.topSets = device.topSets
        rollup.checkIn = device.checkIn
        rollup.readiness = device.readiness
        rollup.wins = WinsCalculator.wins(for: rollup, goals: goals)
        return rollup
    }

    /// An empty day for `date`, for the common case where nothing has been mirrored yet.
    public static func empty(date: CalendarDate, goals: GoalSettingsDocument,
                             clock: some SyncClock) -> DayRollup {
        DayRollup(date: date, timezone: goals.timezone, updatedAt: clock.timestamp,
                  wins: Wins(session: false, protein: false, steps: false, sleep: false))
    }

    /// Water is the one field both halves can supply: HealthKit mirrors every
    /// `dietaryWater` sample, including the ones this app wrote. The mirror is therefore
    /// the fuller number and wins; the logged total is the fallback for a day HealthKit has
    /// not caught up with.
    private static func merged(measuredWater: Double?, logged: NutritionRollup) -> NutritionRollup {
        var nutrition = logged
        nutrition.waterMl = measuredWater ?? logged.waterMl
        return nutrition
    }
}
