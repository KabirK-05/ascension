import AscensionCore
import Foundation

@testable import AscensionEngines

/// Inputs for the engine tests.
///
/// 2026-11-09 is a Monday, which the seeded program plans as Upper A — so it is the
/// anchor every readiness case is built around, and `isoWeekday` is asserted against it
/// in `CalendarMathTests`.
enum Fix {
    static let goals = Seed.goalSettings
    static let program = Seed.program
    static let sessions = Set(Seed.program.sessions.keys)

    static let monday = CalendarDate.literal("2026-11-09")
    static let mondayMorning = "2026-11-09T07:00:00-05:00"

    static func date(_ raw: String) -> CalendarDate { CalendarDate.literal(raw) }
    static func stamp(_ raw: String) -> Timestamp { Timestamp.literal(raw) }

    static func clock(_ raw: String = mondayMorning) -> EngineClock {
        EngineClock(now: stamp(raw), timezone: Seed.timezone)
    }

    // MARK: - Check-in

    static func soreness(sore: [MuscleGroup] = [], mild: [MuscleGroup] = []) -> Soreness {
        var levels = Soreness()
        for group in mild { levels = set(levels, group, .mild) }
        for group in sore { levels = set(levels, group, .sore) }
        return levels
    }

    static func checkIn(energy: Int = 4,
                        sore: [MuscleGroup] = [],
                        mild: [MuscleGroup] = []) -> CheckInRollup {
        CheckInRollup(energy: energy, soreness: soreness(sore: sore, mild: mild))
    }

    private static func set(_ levels: Soreness,
                            _ group: MuscleGroup,
                            _ level: SorenessLevel) -> Soreness {
        var copy = levels
        switch group {
        case .chest: copy.chest = level
        case .back: copy.back = level
        case .shoulders: copy.shoulders = level
        case .arms: copy.arms = level
        case .quads: copy.quads = level
        case .hamstrings: copy.hamstrings = level
        case .glutes: copy.glutes = level
        case .core: copy.core = level
        }
        return copy
    }

    // MARK: - Readiness input

    /// A well-rested Monday with every signal measured: the baseline every case varies
    /// from. Scores in the high nineties, so the default verdict is `trainAsPlanned`.
    static func input(now: String = mondayMorning,
                      planned: SessionKind? = .upperA,
                      programSessions: Set<SessionKind>? = nil,
                      asleepMinutes: Int? = 462,
                      consistencySd7Minutes: Double? = 28,
                      hrvSdnnMs: Double? = 42,
                      hrvBaseline: Double? = 41,
                      restingHrBpm: Int? = 56,
                      restingHrBaseline: Double? = 58,
                      yesterdayLoadAu: Double? = 0,
                      loadBaseline: Double? = 6_000,
                      checkIn: CheckInRollup? = checkIn(),
                      lastTrainedAt: [MuscleRegion: Timestamp] = [:]) -> ReadinessInput {
        ReadinessInput(
            clock: clock(now),
            plannedSession: planned,
            programSessions: programSessions ?? sessions,
            sleep: SleepRollup(asleepMinutes: asleepMinutes,
                               consistencySd7Minutes: consistencySd7Minutes),
            vitals: VitalsRollup(restingHrBpm: restingHrBpm, hrvSdnnMs: hrvSdnnMs),
            baselines: ReadinessBaselines(hrvSdnnMs: hrvBaseline,
                                          restingHrBpm: restingHrBaseline,
                                          trainingDayLoadAu: loadBaseline),
            checkIn: checkIn,
            yesterdayLoadAu: yesterdayLoadAu,
            lastTrainedAt: lastTrainedAt,
            targets: goals.targets)
    }

    /// An input whose score moves only with sleep, every other factor pinned at full
    /// marks. Coverage is 0.9, so confidence is `high` and the verdict is decided by the
    /// score band alone. Spans scores 72–100, which straddles the train-as-planned
    /// threshold.
    static func highDial(asleepMinutes: Int) -> ReadinessInput {
        input(asleepMinutes: asleepMinutes,
              consistencySd7Minutes: 30,
              hrvSdnnMs: 45,
              hrvBaseline: 41,
              restingHrBpm: 54,
              restingHrBaseline: 58,
              yesterdayLoadAu: nil,
              loadBaseline: nil,
              checkIn: checkIn(energy: 5))
    }

    /// The same idea at the other end: every factor but soreness and yesterday's load
    /// pinned at zero marks, fully measured. Spans scores 20–45, which straddles the
    /// active-recovery floor. Nothing is marked sore, so the plan stays legal and the
    /// floor is the only thing deciding.
    static func lowDial(asleepMinutes: Int) -> ReadinessInput {
        input(asleepMinutes: asleepMinutes,
              consistencySd7Minutes: 100,
              hrvSdnnMs: 32,
              hrvBaseline: 41,
              restingHrBpm: 70,
              restingHrBaseline: 58,
              yesterdayLoadAu: 0,
              loadBaseline: 6_000,
              checkIn: checkIn(energy: 1))
    }

    /// Nothing measured at all.
    static func blindInput(planned: SessionKind? = .upperA) -> ReadinessInput {
        input(planned: planned,
              asleepMinutes: nil,
              consistencySd7Minutes: nil,
              hrvSdnnMs: nil,
              hrvBaseline: nil,
              restingHrBpm: nil,
              restingHrBaseline: nil,
              yesterdayLoadAu: nil,
              loadBaseline: nil,
              checkIn: nil)
    }

    // MARK: - Rollups

    static func rollup(date: CalendarDate,
                       weightKg: Double? = nil,
                       proteinG: Double? = nil,
                       asleepMinutes: Int? = nil,
                       consistencySd7Minutes: Double? = nil,
                       restingHrBpm: Int? = nil,
                       hrvSdnnMs: Double? = nil,
                       vo2Max: Double? = nil,
                       sessionPlanned: SessionKind? = nil,
                       sessionDone: Bool = false,
                       loadAu: Double? = nil,
                       workouts: [WorkoutSummary] = []) -> DayRollup {
        DayRollup(date: date,
                  timezone: Seed.timezone,
                  updatedAt: stamp("\(date.rawValue)T23:05:00-05:00"),
                  nutrition: NutritionRollup(proteinG: proteinG),
                  activity: ActivityRollup(),
                  sleep: SleepRollup(asleepMinutes: asleepMinutes,
                                     consistencySd7Minutes: consistencySd7Minutes),
                  vitals: VitalsRollup(restingHrBpm: restingHrBpm, hrvSdnnMs: hrvSdnnMs,
                                       vo2Max: vo2Max),
                  body: BodyRollup(weightKg: weightKg),
                  training: TrainingRollup(sessionPlanned: sessionPlanned,
                                           sessionDone: sessionDone,
                                           loadAu: loadAu,
                                           workouts: workouts),
                  wins: Wins(session: false, protein: false, steps: false, sleep: false))
    }

    static func workout(on date: CalendarDate,
                        startHour: Int = 19,
                        durationMinutes: Int = 50,
                        hrAvgBpm: Int? = 120) -> WorkoutSummary {
        let start = stamp("\(date.rawValue)T\(String(format: "%02d", startHour)):00:00-05:00")
        let endHour = startHour + 1
        let end = stamp("\(date.rawValue)T\(String(format: "%02d", endHour)):00:00-05:00")
        return WorkoutSummary(healthKitId: "fixture-\(date.rawValue)-\(startHour)",
                              type: "traditionalStrengthTraining",
                              startedAt: start,
                              endedAt: end,
                              durationMinutes: durationMinutes,
                              hrAvgBpm: hrAvgBpm,
                              source: "Apple Workout")
    }

    /// `count` days of weigh-ins ending on `endingOn`, each `dailyChangeKg` from the last.
    static func weighIns(startKg: Double,
                         dailyChangeKg: Double,
                         count: Int,
                         endingOn: CalendarDate) -> [DayRollup] {
        (0..<count).map { index in
            let date = endingOn.adding(days: -(count - 1 - index))
            return rollup(date: date, weightKg: startKg + dailyChangeKg * Double(index))
        }
    }
}
