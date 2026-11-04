import AscensionCore
import Foundation

/// The 30-day baselines readiness is judged against (spec §F5).
///
/// Every field is optional and `nil` means *no baseline yet* — a fresh install, or a
/// metric Apple has not produced enough samples for. A missing baseline removes its
/// metric from the score instead of scoring it as zero.
public struct ReadinessBaselines: Hashable, Sendable {
    /// Mean HRV (SDNN, ms) over the trailing 30 days.
    public var hrvSdnnMs: Double?

    /// Mean resting heart rate (bpm) over the trailing 30 days.
    public var restingHrBpm: Double?

    /// Typical load of a single training day, in the contract's `loadAu` units. The
    /// yardstick yesterday's load is read against.
    public var trainingDayLoadAu: Double?

    public init(hrvSdnnMs: Double? = nil, restingHrBpm: Double? = nil,
                trainingDayLoadAu: Double? = nil) {
        self.hrvSdnnMs = hrvSdnnMs
        self.restingHrBpm = restingHrBpm
        self.trainingDayLoadAu = trainingDayLoadAu
    }
}

/// Everything the readiness engine is allowed to know.
///
/// A value type on purpose: `ReadinessEngine.assess(_:)` is a pure function of this
/// struct, so a verdict is reproducible from an exported day forever. Note what is *not*
/// here — no `Date()`, no HealthKit, no store. The clock is injected.
public struct ReadinessInput: Hashable, Sendable {
    /// The instant and timezone the assessment is made in.
    public var clock: EngineClock

    /// What the program prescribes today. `nil` means the program has no entry for today,
    /// which is treated exactly like a rest day: nothing is prescribed, so nothing is
    /// overridden.
    public var plannedSession: SessionKind?

    /// Session kinds the program defines, i.e. the candidates a swap may choose from.
    public var programSessions: Set<SessionKind>

    /// Last night's sleep.
    public var sleep: SleepRollup

    /// This morning's resting physiology.
    public var vitals: VitalsRollup

    public var baselines: ReadinessBaselines

    /// The morning check-in. `nil` means it has not been filled in yet — soreness is
    /// then *unknown*, which is not the same as "none".
    public var checkIn: CheckInRollup?

    /// Yesterday's `loadAu` (`docs/EXPORT_SCHEMA.md` §1).
    ///
    /// Pass `0` for a day that genuinely carried no training and `nil` when the load could
    /// not be measured — a workout whose heart-rate data is missing, say. The distinction
    /// matters: `0` scores as full recovery, `nil` scores as nothing at all.
    public var yesterdayLoadAu: Double?

    /// When each region was last loaded. A region absent from the map was not trained in
    /// the history the caller looked at, and so counts as fully recovered.
    public var lastTrainedAt: [MuscleRegion: Timestamp]

    /// Daily targets, for the sleep goal the duration factor is scored against.
    public var targets: GoalTargets

    public init(clock: EngineClock,
                plannedSession: SessionKind?,
                programSessions: Set<SessionKind>,
                sleep: SleepRollup = SleepRollup(),
                vitals: VitalsRollup = VitalsRollup(),
                baselines: ReadinessBaselines = ReadinessBaselines(),
                checkIn: CheckInRollup? = nil,
                yesterdayLoadAu: Double? = nil,
                lastTrainedAt: [MuscleRegion: Timestamp] = [:],
                targets: GoalTargets) {
        self.clock = clock
        self.plannedSession = plannedSession
        self.programSessions = programSessions
        self.sleep = sleep
        self.vitals = vitals
        self.baselines = baselines
        self.checkIn = checkIn
        self.yesterdayLoadAu = yesterdayLoadAu
        self.lastTrainedAt = lastTrainedAt
        self.targets = targets
    }
}
