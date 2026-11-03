import AscensionCore
import Foundation

/// Builds a ``ReadinessInput`` out of synced days, so the caller never has to derive a
/// baseline or a last-trained stamp by hand and get it subtly wrong.
///
/// Pure, like everything else here: it reads the rollups it is handed and nothing else.
public enum ReadinessHistory {
    /// Days the HRV and resting-HR baselines average over (spec §F5).
    public static let baselineWindowDays = 30

    /// A `ReadinessInput` assembled from history.
    ///
    /// `history` may be in any order and may include `clock.today`; the day matching the
    /// clock supplies this morning's vitals, sleep and check-in, and the days before it
    /// supply the baselines and the recovery stamps.
    public static func input(history: [DayRollup],
                             clock: EngineClock,
                             program: ProgramDocument,
                             goals: GoalSettingsDocument) -> ReadinessInput {
        let today = history.first { $0.date == clock.today }
        let past = history.filter { $0.date < clock.today }
        let planned = today?.training.sessionPlanned
            ?? program.kind(forWeekday: clock.today.isoWeekday)

        return ReadinessInput(
            clock: clock,
            plannedSession: planned,
            programSessions: Set(program.sessions.keys),
            sleep: today?.sleep ?? SleepRollup(),
            vitals: today?.vitals ?? VitalsRollup(),
            baselines: baselines(past: past, asOf: clock.today),
            checkIn: today?.checkIn,
            yesterdayLoadAu: yesterdayLoadAu(past: past, asOf: clock.today),
            lastTrainedAt: lastTrainedAt(history: history, asOf: clock.today),
            targets: goals.targets)
    }

    /// Trailing means over ``baselineWindowDays``, excluding `asOf` itself.
    ///
    /// Today is excluded on purpose: a baseline that includes today's reading would
    /// partly compare a measurement against itself and flatten exactly the deviation the
    /// score is looking for.
    public static func baselines(past: [DayRollup],
                                 asOf: CalendarDate,
                                 windowDays: Int = baselineWindowDays) -> ReadinessBaselines {
        let window = past.filter { day in
            let distance = day.date.days(until: asOf)
            return distance >= 1 && distance <= windowDays
        }
        return ReadinessBaselines(
            hrvSdnnMs: mean(window.compactMap(\.vitals.hrvSdnnMs)),
            restingHrBpm: mean(window.compactMap(\.vitals.restingHrBpm).map(Double.init)),
            trainingDayLoadAu: mean(window.compactMap(\.training.loadAu).filter { $0 > 0 }))
    }

    /// Yesterday's `loadAu`.
    ///
    /// Three outcomes, and the difference between the last two is the one that matters:
    /// a measured load; `0` for a day that carried no workout at all; `nil` when a workout
    /// landed but its load could not be computed, or when yesterday is simply not in the
    /// history. `nil` drops the term from the score rather than scoring it as rest.
    public static func yesterdayLoadAu(past: [DayRollup], asOf: CalendarDate) -> Double? {
        let yesterday = asOf.adding(days: -1)
        guard let day = past.first(where: { $0.date == yesterday }) else { return nil }
        if let load = day.training.loadAu { return load }
        return day.training.workouts.isEmpty ? 0 : nil
    }

    /// The most recent moment each region was loaded, at or before `asOf`.
    ///
    /// A day counts as having loaded a region when a session was done and the program
    /// kind recorded for that day loads it. The moment is the last workout's end where
    /// HealthKit supplied one; otherwise the end of that local day.
    ///
    /// End of day, not start: a later stamp means fewer hours of recovery have elapsed,
    /// which is the reading that holds training back rather than waving it through.
    public static func lastTrainedAt(history: [DayRollup],
                                     asOf: CalendarDate) -> [MuscleRegion: Timestamp] {
        var result: [MuscleRegion: Timestamp] = [:]
        let candidates = history
            .filter { $0.date <= asOf && $0.training.sessionDone }
            .sorted { $0.date < $1.date }

        for day in candidates {
            guard let kind = day.training.sessionPlanned, let stamp = sessionEnd(of: day) else {
                continue
            }
            for region in kind.trainedRegions {
                result[region] = stamp
            }
        }
        return result
    }

    /// When the day's training finished.
    private static func sessionEnd(of day: DayRollup) -> Timestamp? {
        let ends = day.training.workouts.map(\.endedAt.rawValue).sorted()
        if let last = ends.last, let stamp = Timestamp(rawValue: last) { return stamp }
        return endOfDay(day)
    }

    /// `23:59:00` on the day's own date, carrying the offset its own `updatedAt` stamp
    /// uses — so the arithmetic stays in the user's timezone without this module ever
    /// touching a timezone database.
    private static func endOfDay(_ day: DayRollup) -> Timestamp? {
        let stamp = day.updatedAt.rawValue
        let offset = stamp.hasSuffix("Z") ? "Z" : String(stamp.suffix(6))
        return Timestamp(rawValue: "\(day.date.rawValue)T23:59:00\(offset)")
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
