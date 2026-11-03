import AscensionCore
import AscensionEngines
import Foundation

/// Synthetic histories for previews and tests.
///
/// Generated, never recorded: `docs/DESIGN_RULES.md` and `CLAUDE.md` both forbid real
/// health data in the repository. Every number here is produced by the generator below
/// from a handful of parameters, so a fixture describes a *shape* — a steady cut, a
/// layoff, a stalled fortnight — rather than a copied week.
public enum TrendsFixtures {

    /// The anchor every fixture is built back from. 2026-12-05 is a Saturday, so the
    /// review card is absent unless a fixture asks for the Sunday after it.
    public static let saturday = CalendarDate.literal("2026-12-05")

    /// 2026-12-06, a Sunday: the day the weekly review exists.
    public static let sunday = CalendarDate.literal("2026-12-06")

    /// Losing steadily, training on program, protein mostly held. Nothing is wrong, so
    /// the engine proposes no calorie change and the tab is four cards.
    public static let cutting = snapshot(asOf: saturday, shape: Shape())

    /// Two weeks under 0.3 kg/week, which is what makes the engine suggest 2,000 kcal.
    public static let stalled = snapshot(asOf: saturday,
                                         shape: Shape(startWeightKg: 74.2,
                                                      kgPerWeek: -0.1))

    /// Back training after nine days off: the spike warning, and no chronic load to
    /// divide by.
    public static let layoff = snapshot(asOf: saturday, shape: Shape(layoffDays: 9))

    /// The Sunday review, on a week that produces a calorie suggestion.
    public static let sundayReview = snapshot(asOf: sunday,
                                              shape: Shape(startWeightKg: 74.2,
                                                           kgPerWeek: -0.1))

    /// What a generated history looks like.
    public struct Shape: Sendable {
        /// Days of history, ending on the snapshot's day.
        public var days = 35

        public var startWeightKg = 75.4
        public var kgPerWeek = -0.5

        /// How much a single weigh-in wanders from the trend. Deterministic.
        public var dailyNoiseKg = 0.35

        /// Days in every seven with no weigh-in at all.
        public var missedWeighIns = 1

        /// Days in every seven the protein floor is missed.
        public var missedProteinDays = 2

        /// Planned sessions skipped, counted back from the most recent.
        public var skippedSessions = 1

        /// Consecutive days off, immediately before the last three days.
        public var layoffDays = 0

        public init() {}

        public init(days: Int = 35,
                    startWeightKg: Double = 75.4,
                    kgPerWeek: Double = -0.5,
                    missedProteinDays: Int = 2,
                    skippedSessions: Int = 1,
                    layoffDays: Int = 0) {
            self.days = days
            self.startWeightKg = startWeightKg
            self.kgPerWeek = kgPerWeek
            self.missedProteinDays = missedProteinDays
            self.skippedSessions = skippedSessions
            self.layoffDays = layoffDays
        }
    }

    /// A snapshot whose history is generated from `shape`.
    public static func snapshot(asOf: CalendarDate,
                                shape: Shape = Shape(),
                                goals: GoalSettingsDocument = Seed.goalSettings,
                                program: ProgramDocument = Seed.program,
                                flags: FlagsDocument = Seed.flags) -> TrendsSnapshot {
        TrendsSnapshot(clock: clock(asOf: asOf, timezone: goals.timezone),
                       goals: goals,
                       program: program,
                       flags: flags,
                       history: history(asOf: asOf, shape: shape,
                                        goals: goals, program: program))
    }

    /// Eight in the morning on `asOf`, in the user's offset.
    public static func clock(asOf: CalendarDate, timezone: String = Seed.timezone) -> EngineClock {
        EngineClock(now: Timestamp.literal("\(asOf.rawValue)T08:00:00-05:00"),
                    timezone: timezone)
    }

    // MARK: - Generation

    static func history(asOf: CalendarDate,
                        shape: Shape,
                        goals: GoalSettingsDocument,
                        program: ProgramDocument) -> [DayRollup] {
        let dates = asOf.trailingWindow(days: max(1, shape.days))
        let layoffRange = layoff(in: dates, days: shape.layoffDays)
        var plannedSeen = 0

        return dates.enumerated().reversed().compactMap { index, date -> DayRollup? in
            let daysBack = dates.count - 1 - index
            let planned = program.kind(forWeekday: date.isoWeekday)
            let isTraining = planned?.isTrainingDay == true && !layoffRange.contains(date.rawValue)
            if planned?.isTrainingDay == true { plannedSeen += 1 }
            let done = isTraining && plannedSeen > shape.skippedSessions

            let protein = daysBack % 7 < shape.missedProteinDays
                ? Double(goals.targets.proteinMinG) - 22
                : Double(goals.targets.proteinG) + Double((daysBack * 3) % 11) - 5
            let sleepMinutes = Self.sleep(daysBack: daysBack)
            let restingHr = Self.restingHr(daysBack: daysBack)

            let workouts = done ? [workout(on: date, minutes: 52 + (daysBack % 3) * 6,
                                           hrAvg: 128 + (daysBack % 4) * 5)] : []

            return DayRollup(
                date: date,
                timezone: goals.timezone,
                updatedAt: Timestamp.literal("\(date.rawValue)T22:00:00-05:00"),
                nutrition: NutritionRollup(kcal: Double(goals.targets.kcal) - 60,
                                           proteinG: protein),
                activity: ActivityRollup(steps: 9_200 + (daysBack * 431) % 3_800,
                                         activeEnergyKcal: 520 + Double((daysBack * 37) % 180),
                                         exerciseMinutes: done ? 58 : 22),
                sleep: SleepRollup(asleepMinutes: sleepMinutes,
                                   inBedMinutes: sleepMinutes + 24,
                                   consistencySd7Minutes: 26 + Double(daysBack % 9)),
                vitals: VitalsRollup(restingHrBpm: restingHr,
                                     hrvSdnnMs: 40 + Double((daysBack * 7) % 13),
                                     vo2Max: vo2(daysBack: daysBack)),
                body: BodyRollup(weightKg: weighIn(daysBack: daysBack, shape: shape)),
                training: TrainingRollup(sessionPlanned: planned,
                                         sessionDone: done,
                                         loadAu: TrainingRollup.loadAu(workouts: workouts,
                                                                       restingHrBpm: restingHr),
                                         workouts: workouts),
                wins: Wins(session: done || planned?.isTrainingDay == false,
                           protein: protein >= Double(goals.targets.proteinMinG),
                           steps: true,
                           sleep: sleepMinutes >= goals.targets.sleepMinutes))
        }
        .reversed()
    }

    /// The weigh-in `daysBack` days before the end, or `nil` on a day it was skipped.
    ///
    /// The wobble is a sine of the day index rather than a random draw: a fixture has to
    /// produce the same chart on every run, or a snapshot test is testing the generator.
    static func weighIn(daysBack: Int, shape: Shape) -> Double? {
        guard shape.missedWeighIns <= 0 || daysBack % 7 >= shape.missedWeighIns else {
            return nil
        }
        let drift = shape.kgPerWeek / 7 * Double(-daysBack)
        let wobble = sin(Double(daysBack) * 1.3) * shape.dailyNoiseKg
        return ((shape.startWeightKg + drift + wobble) * 10).rounded() / 10
    }

    /// A night's sleep: a slow weekly swing with a shorter wobble on top, rather than the
    /// modulo sawtooth a naive generator produces. A series only has to be *plausible* to
    /// prove a chart works, but a sawtooth proves the opposite — it makes a correct
    /// sparkline look broken.
    static func sleep(daysBack: Int) -> Int {
        let day = Double(daysBack)
        return Int((432 + sin(day * 0.9) * 34 + sin(day * 0.21) * 22).rounded())
    }

    /// Resting heart rate drifts with training load and moves a beat or two a night.
    static func restingHr(daysBack: Int) -> Int {
        let day = Double(daysBack)
        return Int((54 + sin(day * 0.45) * 2.2 + sin(day * 0.13) * 1.4).rounded())
    }

    /// VO₂ max moves slowly and is not measured every day, which is how HealthKit
    /// reports it.
    static func vo2(daysBack: Int) -> Double? {
        guard daysBack % 4 == 0 else { return nil }
        return ((44.6 - Double(daysBack) * 0.02) * 10).rounded() / 10
    }

    static func workout(on date: CalendarDate, minutes: Int, hrAvg: Int) -> WorkoutSummary {
        WorkoutSummary(healthKitId: "fixture-\(date.rawValue)",
                       type: "traditionalStrengthTraining",
                       startedAt: Timestamp.literal("\(date.rawValue)T18:00:00-05:00"),
                       endedAt: Timestamp.literal("\(date.rawValue)T19:00:00-05:00"),
                       durationMinutes: minutes,
                       activeEnergyKcal: Double(minutes) * 7.4,
                       hrAvgBpm: hrAvg,
                       hrMaxBpm: hrAvg + 28,
                       source: "Apple Watch")
    }

    /// The dates inside a layoff, ending three days before the snapshot so training has
    /// visibly resumed on top of it.
    static func layoff(in dates: [CalendarDate], days: Int) -> Set<String> {
        guard days > 0, dates.count > days + 3 else { return [] }
        let end = dates.count - 4
        return Set(dates[max(0, end - days + 1)...end].map(\.rawValue))
    }
}

/// A data source that hands back one fixture.
public struct FixtureTrendsDataSource: TrendsDataSource {
    private let snapshot: TrendsSnapshot

    public init(_ snapshot: TrendsSnapshot) {
        self.snapshot = snapshot
    }

    public func snapshot() async throws -> TrendsSnapshot { snapshot }
}

/// An acceptor that does nothing, for previews.
public struct NoopAcceptor: SuggestionAcceptor {
    public init() {}
    public func accept(suggestionId: String) async throws {}
}
