import AscensionCore
import AscensionEngines
import Foundation

/// Deterministic data for previews, screenshots and tests.
///
/// Fixed dates and a seeded generator, so a preview looks identical in every run and a
/// reviewer comparing two screenshots is comparing the design, not the dice. Nothing
/// here is shipped behaviour: the app injects a real ``TodayDataSource``.
enum TodayFixtures {
    static let timezone = Seed.timezone

    /// A Tuesday, which the seeded program prescribes as Lower A.
    static let tuesday = CalendarDate.literal("2026-11-03")
    /// A Sunday, which the seeded program prescribes as rest.
    static let sunday = CalendarDate.literal("2026-11-08")

    static func clock(on day: CalendarDate, at time: String = "18:20:00") -> EngineClock {
        EngineClock(now: Timestamp.literal("\(day.rawValue)T\(time)-05:00"), timezone: timezone)
    }

    // MARK: - Snapshots

    /// Rested, on programme, mid-evening: the ordinary case.
    static var trainingDay: TodaySnapshot {
        snapshot(on: tuesday,
                 today: today(on: tuesday,
                              asleepMinutes: 462,
                              bedtimeSd: 24,
                              steps: 8_420,
                              activeEnergy: 512,
                              exerciseMinutes: 34,
                              kcal: 1_610,
                              proteinG: 96,
                              restingHr: 52,
                              hrvSdnn: 68,
                              checkIn: CheckInRollup(energy: 4, soreness: Soreness())))
    }

    /// A rest day the program planned. The engine answers `trainAsPlanned` here, because
    /// nothing is prescribed to cap — the screen must not repeat that back literally.
    static var restDay: TodaySnapshot {
        snapshot(on: sunday,
                 today: today(on: sunday,
                              asleepMinutes: 488,
                              bedtimeSd: 19,
                              steps: 11_900,
                              activeEnergy: 388,
                              exerciseMinutes: 22,
                              kcal: 1_980,
                              proteinG: 141,
                              restingHr: 50,
                              hrvSdnn: 79,
                              checkIn: CheckInRollup(energy: 5, soreness: Soreness())))
    }

    /// Slept fine, legs wrecked, on a Lower A day: the lower body is out on both the
    /// soreness rule and the 48 h rule, so the engine offers the legal upper session and
    /// the card below the score has to follow it rather than still saying Lower A.
    static var soreDay: TodaySnapshot {
        let soreness = Soreness(quads: .sore, glutes: .sore)
        return snapshot(on: tuesday,
                        today: today(on: tuesday,
                                     asleepMinutes: 436,
                                     bedtimeSd: 26,
                                     steps: 6_240,
                                     activeEnergy: 300,
                                     exerciseMinutes: 20,
                                     kcal: 1_180,
                                     proteinG: 78,
                                     restingHr: 54,
                                     hrvSdnn: 66,
                                     checkIn: CheckInRollup(energy: 3, soreness: soreness)),
                        lastTrainedAt: [.upperBody: Timestamp.literal("2026-10-30T19:10:00-05:00"),
                                        .lowerBody: Timestamp.literal("2026-11-02T19:40:00-05:00")])
    }

    /// Tuesday morning, before the check-in. Sleep and vitals are already read, so the
    /// score stands on them while soreness and energy — fifteen of the hundred points —
    /// are still waiting on the one tap this screen exists to collect.
    static var checkInPending: TodaySnapshot {
        var snapshot = snapshot(on: tuesday,
                                today: today(on: tuesday,
                                             asleepMinutes: 448,
                                             bedtimeSd: 22,
                                             steps: 1_240,
                                             activeEnergy: 86,
                                             exerciseMinutes: 4,
                                             kcal: 320,
                                             proteinG: 32,
                                             restingHr: 51,
                                             hrvSdnn: 70,
                                             checkIn: CheckInRollup(energy: 4,
                                                                    soreness: Soreness())))
        snapshot.clock = clock(on: tuesday, at: "07:30:00")
        snapshot.today.checkIn = nil
        return snapshot
    }

    /// Everything measured and most of it bad, on a training day: the score falls under
    /// the floor, so nothing is trained however legal the session is.
    static var standDown: TodaySnapshot {
        snapshot(on: tuesday,
                 today: today(on: tuesday,
                              asleepMinutes: 260,
                              bedtimeSd: 70,
                              steps: 2_100,
                              activeEnergy: 120,
                              exerciseMinutes: 6,
                              kcal: 740,
                              proteinG: 41,
                              restingHr: 62,
                              hrvSdnn: 45,
                              checkIn: CheckInRollup(energy: 2, soreness: Soreness())))
    }

    /// First launch: the seed is installed, nothing has been measured.
    static var emptyDay: TodaySnapshot {
        TodaySnapshot(clock: clock(on: tuesday, at: "07:05:00"),
                      goals: Seed.goalSettings,
                      program: Seed.program,
                      today: blank(on: tuesday))
    }

    // MARK: - Building blocks

    static func snapshot(
        on day: CalendarDate,
        today: DayRollup,
        lastTrainedAt: [MuscleRegion: Timestamp] = [
            .upperBody: Timestamp.literal("2026-11-02T19:10:00-05:00"),
            .lowerBody: Timestamp.literal("2026-10-30T19:40:00-05:00")
        ]
    ) -> TodaySnapshot {
        TodaySnapshot(clock: clock(on: day),
                      goals: Seed.goalSettings,
                      program: Seed.program,
                      today: today,
                      history: history(endingOn: day),
                      baselines: ReadinessBaselines(hrvSdnnMs: 71,
                                                    restingHrBpm: 53,
                                                    trainingDayLoadAu: 240),
                      lastTrainedAt: lastTrainedAt,
                      yesterdayLoadAu: 268)
    }

    static func blank(on day: CalendarDate) -> DayRollup {
        DayRollup(date: day,
                  timezone: timezone,
                  updatedAt: Timestamp.literal("\(day.rawValue)T07:05:00-05:00"),
                  training: TrainingRollup(sessionPlanned: Seed.program.kind(forWeekday: day.isoWeekday)),
                  wins: Wins(session: false, protein: false, steps: false, sleep: false))
    }

    // swiftlint:disable:next function_parameter_count
    static func today(on day: CalendarDate,
                      asleepMinutes: Int,
                      bedtimeSd: Double,
                      steps: Int,
                      activeEnergy: Double,
                      exerciseMinutes: Int,
                      kcal: Double,
                      proteinG: Double,
                      restingHr: Int,
                      hrvSdnn: Double,
                      checkIn: CheckInRollup) -> DayRollup {
        DayRollup(date: day,
                  timezone: timezone,
                  updatedAt: Timestamp.literal("\(day.rawValue)T18:20:00-05:00"),
                  nutrition: NutritionRollup(kcal: kcal, proteinG: proteinG,
                                             fatG: 54, carbsG: 162),
                  activity: ActivityRollup(steps: steps, activeEnergyKcal: activeEnergy,
                                           exerciseMinutes: exerciseMinutes, standHours: 9),
                  sleep: SleepRollup(asleepMinutes: asleepMinutes,
                                     inBedMinutes: asleepMinutes + 28,
                                     consistencySd7Minutes: bedtimeSd),
                  vitals: VitalsRollup(restingHrBpm: restingHr, hrvSdnnMs: hrvSdnn, vo2Max: 41.2),
                  body: BodyRollup(weightKg: 73.8, weightAvg7Kg: 73.6, rateKgPerWeek: -0.34),
                  training: TrainingRollup(sessionPlanned: Seed.program.kind(forWeekday: day.isoWeekday)),
                  checkIn: checkIn,
                  wins: Wins(session: false, protein: false, steps: false, sleep: false))
            .withComputedWins(goals: Seed.goalSettings)
    }

    /// The grid's window, ending the day before `day` — today's own cell comes from the
    /// live rollup, not from history.
    static func history(endingOn day: CalendarDate) -> [DayRollup] {
        var generator = Seeded(state: 0xA5CE_9D01)
        return (1...TodaySnapshot.historyDays).reversed().map { back -> DayRollup in
            let date = day.adding(days: -back)
            let planned = Seed.program.kind(forWeekday: date.isoWeekday)
            // The first fortnight of the window predates the app, so it holds nothing.
            guard back < TodaySnapshot.historyDays - 13 else { return blank(on: date) }
            let done = planned?.isTrainingDay == true && generator.next() % 10 >= 2
            return DayRollup(
                date: date,
                timezone: timezone,
                updatedAt: Timestamp.literal("\(date.rawValue)T23:50:00-05:00"),
                nutrition: NutritionRollup(kcal: 1_780 + Double(generator.next() % 620),
                                           proteinG: 112 + Double(generator.next() % 58)),
                activity: ActivityRollup(steps: 6_200 + Int(generator.next() % 8_400),
                                         activeEnergyKcal: 320 + Double(generator.next() % 420),
                                         exerciseMinutes: 12 + Int(generator.next() % 52)),
                sleep: SleepRollup(asleepMinutes: 372 + Int(generator.next() % 134),
                                   consistencySd7Minutes: 16 + Double(generator.next() % 34)),
                training: TrainingRollup(sessionPlanned: planned, sessionDone: done),
                wins: Wins(session: false, protein: false, steps: false, sleep: false))
                .withComputedWins(goals: Seed.goalSettings)
        }
    }
}

/// A tiny linear congruential generator. Seeded, so previews never flicker.
struct Seeded {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}

/// Serves a fixture. Previews and tests inject this where the app injects the shell's.
struct FixtureDataSource: TodayDataSource {
    let snapshotValue: TodaySnapshot

    init(_ snapshotValue: TodaySnapshot) {
        self.snapshotValue = snapshotValue
    }

    func snapshot() async throws -> TodaySnapshot { snapshotValue }
}

/// Keeps what it was handed, so a test can assert the committed check-in is the one the
/// taps built — group by group, not just "something was saved".
actor RecordingCheckInStore: CheckInStore {
    private(set) var saved: [CheckInRollup] = []
    private(set) var dates: [CalendarDate] = []

    func save(_ checkIn: CheckInRollup, on date: CalendarDate) async throws {
        saved.append(checkIn)
        dates.append(date)
    }
}

/// A store whose first `failures` writes throw. Counts its attempts, so a retry can be
/// shown to have actually gone back to the store.
actor UnreliableCheckInStore: CheckInStore {
    struct Failure: Error {}

    private(set) var attempts = 0
    private var failuresRemaining: Int

    init(failures: Int = Int.max) {
        self.failuresRemaining = failures
    }

    func save(_ checkIn: CheckInRollup, on date: CalendarDate) async throws {
        attempts += 1
        guard failuresRemaining > 0 else { return }
        failuresRemaining -= 1
        throw Failure()
    }
}
