import AscensionCore
import Foundation

/// Everything HealthKit knows about one day, in the contract's shapes.
///
/// `gaps` is the honest half: a metric listed there has no value, and the reason is at
/// best "no data or no permission". Nothing in this type reads as zero when it means
/// unknown.
public struct DayHealthSnapshot: Hashable, Sendable {
    public var date: CalendarDate
    public var timezone: String
    public var activity: ActivityRollup
    public var sleep: SleepRollup
    public var vitals: VitalsRollup
    public var body: BodyRollup
    /// Dietary water, the one nutrition field HealthKit is the source for.
    public var waterMl: Double?
    public var workouts: [WorkoutMirror]
    public var night: SleepNight?
    public var weight: WeightPoint?
    public var gaps: [HealthMetric: ReadingGap]

    public init(date: CalendarDate, timezone: String,
                activity: ActivityRollup = ActivityRollup(),
                sleep: SleepRollup = SleepRollup(),
                vitals: VitalsRollup = VitalsRollup(),
                body: BodyRollup = BodyRollup(),
                waterMl: Double? = nil,
                workouts: [WorkoutMirror] = [],
                night: SleepNight? = nil,
                weight: WeightPoint? = nil,
                gaps: [HealthMetric: ReadingGap] = [:]) {
        self.date = date
        self.timezone = timezone
        self.activity = activity
        self.sleep = sleep
        self.vitals = vitals
        self.body = body
        self.waterMl = waterMl
        self.workouts = workouts
        self.night = night
        self.weight = weight
        self.gaps = gaps
    }

    public var mirrors: MirrorSet {
        MirrorSet(workouts: workouts,
                  nights: night.map { [$0] } ?? [],
                  weights: weight.map { [$0] } ?? [])
    }

    /// Fills the HealthKit-owned parts of a `DayRollup` and leaves the rest alone.
    ///
    /// Logged food, the check-in, readiness and `wins` belong to other modules; this
    /// writes activity, sleep, vitals, body, `nutrition.waterMl` and the mirrored
    /// workouts, and touches nothing else. `loadAu` is recomputed because it is a
    /// function of the workouts and the resting heart rate this snapshot just supplied.
    public func applied(to rollup: DayRollup, timeZone: TimeZone) -> DayRollup {
        var updated = rollup
        updated.activity = activity
        updated.sleep = SleepRollup(asleepMinutes: sleep.asleepMinutes,
                                    inBedMinutes: sleep.inBedMinutes,
                                    consistencySd7Minutes: rollup.sleep.consistencySd7Minutes)
        updated.vitals = vitals
        updated.body = BodyRollup(weightKg: body.weightKg,
                                  weightAvg7Kg: rollup.body.weightAvg7Kg,
                                  rateKgPerWeek: rollup.body.rateKgPerWeek,
                                  bodyFatPct: body.bodyFatPct,
                                  waistCm: body.waistCm)
        updated.nutrition.waterMl = waterMl
        let summaries = workouts.map { $0.summary(timeZone: timeZone) }
        updated.training.workouts = summaries
        updated.training.loadAu = TrainingRollup.loadAu(workouts: summaries,
                                                        restingHrBpm: vitals.restingHrBpm)
        return updated
    }
}
