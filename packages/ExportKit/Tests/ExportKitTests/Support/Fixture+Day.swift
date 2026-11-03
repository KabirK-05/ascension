import AscensionCore
import Foundation

@testable import ExportKit

extension Fixture {
    /// Days the user planned to train and did not — both Thursdays, so the miss really
    /// lands on a session. Two misses in four weeks is the kind of adherence the
    /// summary has to render honestly.
    static let missedSessionOffsets: Set<Int> = [9, 16]
    /// A day with nothing logged at all — no food, no readiness, no check-in.
    static let unloggedOffset = 20

    static func monthRollup(date: CalendarDate, offset: Int) -> DayRollup {
        let planned = plannedSession(on: date)
        let trained = (planned?.isTrainingDay ?? false)
            && !missedSessionOffsets.contains(offset)
            && offset != unloggedOffset
        let logged = offset != unloggedOffset

        let nutrition = logged
            ? NutritionRollup(kcal: Double(2_050 + (offset * 53) % 300),
                              proteinG: Double(132 + (offset * 11) % 30),
                              fatG: Double(61 + (offset * 7) % 9),
                              carbsG: Double(230 + (offset * 29) % 40),
                              waterMl: Double(2_000 + (offset * 97) % 900))
            : NutritionRollup()
        let activity = ActivityRollup(steps: 8_600 + (offset * 137) % 3_400,
                                      activeEnergyKcal: Double(520 + (offset * 31) % 180),
                                      exerciseMinutes: trained ? 52 : 18,
                                      standHours: 9 + offset % 4)
        let sleep = SleepRollup(asleepMinutes: 410 + (offset * 17) % 80,
                                inBedMinutes: 440 + (offset * 17) % 80,
                                consistencySd7Minutes: Double(28 + offset % 12))
        let vitals = VitalsRollup(restingHrBpm: 56 + offset % 5,
                                  hrvSdnnMs: offset % 9 == 3 ? nil : Double(38 + offset % 9),
                                  vo2Max: 44.2,
                                  respiratoryRate: 14.1,
                                  spo2Pct: 97)
        let body = BodyRollup(weightKg: rounded(74.4 - Double(offset) * 0.03),
                              weightAvg7Kg: rounded(74.5 - Double(offset) * 0.028),
                              rateKgPerWeek: -0.4)
        let training = monthTraining(date: date, offset: offset,
                                     planned: planned, trained: trained,
                                     restingHrBpm: vitals.restingHrBpm)

        return DayRollup(
            date: date, timezone: Seed.timezone,
            updatedAt: Timestamp.literal("\(date.rawValue)T23:05:00-05:00"),
            nutrition: nutrition, activity: activity, sleep: sleep,
            vitals: vitals, body: body, training: training,
            checkIn: logged && offset % 5 != 2 ? monthCheckIn(offset: offset) : nil,
            readiness: logged ? monthReadiness(offset: offset, sleep: sleep) : nil,
            wins: wins(planned: planned, trained: trained,
                       nutrition: nutrition, activity: activity, sleep: sleep))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// The §1 win rules, applied to the fixture's own numbers so the generated days and
    /// their `wins` can never disagree.
    private static func wins(planned: SessionKind?, trained: Bool,
                             nutrition: NutritionRollup, activity: ActivityRollup,
                             sleep: SleepRollup) -> Wins {
        let targets = Seed.goalSettings.targets
        let session = trained || (planned == .rest && !trained)
        return Wins(session: session,
                    protein: (nutrition.proteinG ?? 0) >= Double(targets.proteinMinG),
                    steps: (activity.steps ?? 0) >= targets.steps,
                    sleep: (sleep.asleepMinutes ?? 0) >= targets.sleepMinutes)
    }

    private static func monthTraining(date: CalendarDate, offset: Int,
                                      planned: SessionKind?, trained: Bool,
                                      restingHrBpm: Int?) -> TrainingRollup {
        guard trained else {
            return TrainingRollup(sessionPlanned: planned, sessionDone: false)
        }
        let workout = monthWorkout(date: date, offset: offset, planned: planned)
        // The contract's own formula, rounded the way the app will store it.
        let load = TrainingRollup.loadAu(workouts: [workout], restingHrBpm: restingHrBpm)
        return TrainingRollup(
            sessionPlanned: planned,
            sessionDone: true,
            loadAu: load.map { ($0 * 10).rounded() / 10 },
            workouts: [workout],
            topSets: planned == .zone2 ? [] : monthTopSets(offset: offset, planned: planned))
    }

    private static func monthWorkout(date: CalendarDate, offset: Int,
                                     planned: SessionKind?) -> WorkoutSummary {
        let isZone2 = planned == .zone2
        let duration = isZone2 ? 45 : 48 + offset % 9
        return WorkoutSummary(
            healthKitId: String(format: "A1B2C3D4-0000-0000-0000-%012d", offset + 1),
            type: isZone2 ? "walking" : "traditionalStrengthTraining",
            startedAt: Timestamp.literal("\(date.rawValue)T19:04:00-05:00"),
            // Derived from the duration, so the journal's window and its minute figure
            // cannot contradict each other.
            endedAt: Timestamp.literal(
                "\(date.rawValue)T\(clockTime(minutesAfter1904: duration)):00-05:00"),
            durationMinutes: duration,
            activeEnergyKcal: Double(340 + (offset * 13) % 70),
            hrAvgBpm: isZone2 ? 112 : 118 + offset % 7,
            hrMaxBpm: isZone2 ? 128 : 146 + offset % 9,
            timeInZonesMinutes: TimeInZonesMinutes(z1: 4, z2: 22, z3: 18, z4: 6, z5: 1),
            source: "Apple Workout")
    }

    private static func monthTopSets(offset: Int, planned: SessionKind?) -> [TopSet] {
        let upper = planned == .upperA || planned == .upperB
        let increment = Double((offset / 7)) * 2.5
        return upper
            ? [TopSet(exerciseId: "DB_Bench_Press", weightKg: 20 + increment, reps: 11),
               TopSet(exerciseId: "Lat_Pulldown", weightKg: 45 + increment, reps: 12)]
            : [TopSet(exerciseId: "Goblet_Squat", weightKg: 24 + increment, reps: 12),
               TopSet(exerciseId: "Romanian_Deadlift", weightKg: 22 + increment, reps: 12)]
    }

    /// `19:04` plus `minutes`, as `HH:mm`.
    private static func clockTime(minutesAfter1904 minutes: Int) -> String {
        let total = 19 * 60 + 4 + minutes
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func monthCheckIn(offset: Int) -> CheckInRollup {
        let levels: [SorenessLevel] = [.none, .mild, .sore]
        return CheckInRollup(
            energy: 3 + offset % 3,
            soreness: Soreness(back: levels[offset % 3],
                               quads: levels[(offset + 1) % 3],
                               hamstrings: levels[(offset + 2) % 3]))
    }

    private static func monthReadiness(offset: Int, sleep: SleepRollup) -> ReadinessRollup {
        let score = 68 + (offset * 7) % 27
        let verdict: ReadinessVerdict
        switch score {
        case 80...: verdict = .trainAsPlanned
        case 70..<80: verdict = .capIntensity
        case 60..<70: verdict = .swapSession
        default: verdict = .activeRecovery
        }
        let hours = Format.duration(minutes: sleep.asleepMinutes ?? 0)
        return ReadinessRollup(score: score, verdict: verdict,
                               reasons: ["slept \(hours)", "HRV near baseline"])
    }
}
