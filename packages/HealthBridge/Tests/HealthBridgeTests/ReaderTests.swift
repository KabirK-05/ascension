import AscensionCore
import Foundation
import Testing

@testable import HealthBridge

@Suite("the §6 read map feeds the day rollup")
struct ReaderTests {
    private func populatedStore() -> FakeHealthStore {
        let store = FakeHealthStore()
        store.update { config in
            config.quantities = Self.quantities
            config.categories = Self.categories
            config.workouts = [Self.workout]
            config.heartRate = [Self.workout.id: Fixture.heartRateSeries(
                "hr", from: Fixture.instant(hour: 19, minute: 4),
                bpms: [Double](repeating: 120, count: 40), everySeconds: 60)]
        }
        return store
    }

    private static let workout = Fixture.workout("upper-a",
                                                 start: Fixture.instant(hour: 19, minute: 4),
                                                 minutes: 51)

    private static var quantities: [HealthMetric: [QuantityRecord]] {
        let morning = Fixture.instant(hour: 7)
        return [
            .steps: [
                Fixture.quantity("steps-am", metric: .steps, value: 4_240, start: morning),
                Fixture.quantity("steps-pm", metric: .steps, value: 6_000,
                                 start: Fixture.instant(hour: 18))
            ],
            .activeEnergy: [
                Fixture.quantity("ae", metric: .activeEnergy, value: 612, start: morning)
            ],
            .restingEnergy: [
                Fixture.quantity("re", metric: .restingEnergy, value: 1_580, start: morning)
            ],
            .exerciseMinutes: [
                Fixture.quantity("ex", metric: .exerciseMinutes, value: 54, start: morning)
            ],
            .restingHeartRate: [
                Fixture.quantity("rhr-1", metric: .restingHeartRate, value: 57, start: morning),
                Fixture.quantity("rhr-2", metric: .restingHeartRate, value: 59,
                                 start: Fixture.instant(hour: 20))
            ],
            .hrvSdnn: [Fixture.quantity("hrv", metric: .hrvSdnn, value: 41, start: morning)],
            .vo2Max: [
                Fixture.quantity("vo2-old", metric: .vo2Max, value: 43.1,
                                 start: Fixture.instant(hour: 8)),
                Fixture.quantity("vo2-new", metric: .vo2Max, value: 44.2,
                                 start: Fixture.instant(hour: 19))
            ],
            .respiratoryRate: [
                Fixture.quantity("rr", metric: .respiratoryRate, value: 14.1, start: morning)
            ],
            .oxygenSaturation: [
                Fixture.quantity("spo2", metric: .oxygenSaturation, value: 97, start: morning)
            ],
            .bodyMass: [
                Fixture.quantity("weigh", metric: .bodyMass, value: 73.6, start: morning)
            ],
            .dietaryWater: [
                Fixture.quantity("water-1", metric: .dietaryWater, value: 1_200, start: morning),
                Fixture.quantity("water-2", metric: .dietaryWater, value: 1_200,
                                 start: Fixture.instant(hour: 16))
            ]
        ]
    }

    private static var categories: [HealthMetric: [CategoryRecord]] {
        [
            .standHours: (8...17).map {
                Fixture.standHour("stand-\($0)", at: Fixture.instant(hour: $0))
            },
            .sleepAnalysis: [
                Fixture.sleep("core", stage: .asleepCore,
                              start: Fixture.instant(hour: 23, day: 2),
                              end: Fixture.instant(hour: 6, minute: 42)),
                Fixture.sleep("bed", stage: .inBed,
                              start: Fixture.instant(hour: 22, minute: 45, day: 2),
                              end: Fixture.instant(hour: 7))
            ]
        ]
    }

    @Test("each metric is aggregated the way its measurement demands")
    func aggregationPerMetric() async {
        let reader = HealthReader(store: populatedStore(), timeZone: Fixture.timeZone,
                                  zones: Fixture.zones)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))

        // Totals sum; discrete vitals average; body measurements take the newest.
        #expect(snapshot.activity.steps == 10_240)
        #expect(snapshot.activity.activeEnergyKcal == 612)
        #expect(snapshot.activity.exerciseMinutes == 54)
        #expect(snapshot.activity.standHours == 10)
        #expect(snapshot.vitals.restingHrBpm == 58)
        #expect(snapshot.vitals.hrvSdnnMs == 41)
        #expect(snapshot.vitals.vo2Max == 44.2)
        #expect(snapshot.vitals.spo2Pct == 97)
        #expect(snapshot.body.weightKg == 73.6)
        #expect(snapshot.waterMl == 2_400)
    }

    @Test("sleep comes from the night that ended on the day asked about")
    func sleepIsLastNights() async {
        let reader = HealthReader(store: populatedStore(), timeZone: Fixture.timeZone)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))

        #expect(snapshot.sleep.asleepMinutes == 462)
        #expect(snapshot.sleep.inBedMinutes == 495)
        #expect(snapshot.night?.date == Fixture.date("2026-11-03"))
    }

    @Test("an unmeasured metric is a gap, never a zero")
    func unmeasuredIsAGapNotZero() async {
        let store = FakeHealthStore()
        let reader = HealthReader(store: store, timeZone: Fixture.timeZone)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))

        #expect(snapshot.activity.steps == nil)
        #expect(snapshot.body.weightKg == nil)
        #expect(snapshot.gaps[.steps] == .noDataOrNoPermission)
        #expect(snapshot.gaps[.sleepAnalysis] == .noDataOrNoPermission)
    }

    @Test("a denied read and an empty day are the same answer, as HealthKit intends")
    func denialAndEmptinessAreIndistinguishable() async {
        let reader = HealthReader(store: FakeHealthStore(), timeZone: Fixture.timeZone)
        let window = DayWindow(date: Fixture.date("2026-11-03"), timeZone: Fixture.timeZone)
        guard let window else {
            Issue.record("the fixture date must produce a window")
            return
        }
        let reading = await reader.reading(.steps, in: window.interval)
        #expect(reading == .missing(.noDataOrNoPermission))
        #expect(reading.value == nil)
    }

    @Test("a failing query is a gap with its reason, not a crash")
    func failuresBecomeGaps() async {
        let store = populatedStore()
        store.update { $0.failingMetrics = [.steps, .workouts] }
        let reader = HealthReader(store: store, timeZone: Fixture.timeZone)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))

        #expect(snapshot.gaps[.steps] == .queryFailed("fake failure: steps"))
        #expect(snapshot.gaps[.workouts] == .queryFailed("fake failure: workouts"))
        #expect(snapshot.workouts.isEmpty)
        #expect(snapshot.activity.activeEnergyKcal == 612)
    }

    @Test("without HealthKit every reading says so")
    func unavailableStoreReportsUnavailable() async {
        let store = FakeHealthStore(config: .init(available: false))
        let reader = HealthReader(store: store, timeZone: Fixture.timeZone)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))
        #expect(snapshot.gaps[.steps] == .healthDataUnavailable)
    }

    @Test("the snapshot fills the HealthKit half of a DayRollup and leaves the rest")
    func snapshotAppliesToTheContract() async {
        let reader = HealthReader(store: populatedStore(), timeZone: Fixture.timeZone,
                                  zones: Fixture.zones)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))

        let existing = DayRollup(
            date: Fixture.date("2026-11-03"),
            timezone: Fixture.timeZone.identifier,
            updatedAt: Timestamp.literal("2026-11-03T23:05:00-05:00"),
            nutrition: NutritionRollup(kcal: 2_180, proteinG: 148),
            training: TrainingRollup(sessionPlanned: .upperA, sessionDone: true),
            wins: Wins(session: true, protein: true, steps: true, sleep: true))
        let merged = snapshot.applied(to: existing, timeZone: Fixture.timeZone)

        // HealthKit's half is replaced.
        #expect(merged.activity.steps == 10_240)
        #expect(merged.sleep.asleepMinutes == 462)
        #expect(merged.vitals.restingHrBpm == 58)
        #expect(merged.body.weightKg == 73.6)
        #expect(merged.nutrition.waterMl == 2_400)
        #expect(merged.training.workouts.count == 1)
        #expect(merged.training.workouts.first?.timeInZonesMinutes.z2 == 40)

        // Everything another module owns is untouched.
        #expect(merged.nutrition.kcal == 2_180)
        #expect(merged.nutrition.proteinG == 148)
        #expect(merged.training.sessionPlanned == .upperA)
        #expect(merged.wins.total == 4)

        // loadAu follows the contract's formula from the workouts just mirrored.
        #expect(merged.training.loadAu == 51 * (120.0 / 58.0))
    }

    @Test("a day with no workout reports no load rather than a zero")
    func noWorkoutMeansNoLoad() async {
        let reader = HealthReader(store: FakeHealthStore(), timeZone: Fixture.timeZone)
        let snapshot = await reader.snapshot(for: Fixture.date("2026-11-03"))
        let rollup = snapshot.applied(
            to: DayRollup(date: Fixture.date("2026-11-03"),
                          timezone: Fixture.timeZone.identifier,
                          updatedAt: Timestamp.literal("2026-11-03T23:05:00-05:00"),
                          wins: Wins(session: false, protein: false, steps: false, sleep: false)),
            timeZone: Fixture.timeZone)
        #expect(rollup.training.loadAu == nil)
        #expect(rollup.training.workouts.isEmpty)
    }

    @Test("a day window is the user's midnight-to-midnight")
    func dayWindowUsesTheUsersTimezone() {
        guard let window = DayWindow(date: Fixture.date("2026-11-03"), timeZone: Fixture.timeZone) else {
            Issue.record("the fixture date must produce a window")
            return
        }
        #expect(window.interval.duration == 86_400)
        #expect(window.interval.start == Fixture.instant(hour: 0))
        #expect(window.sleepLookback.start == Fixture.instant(hour: 12, day: 2))
        #expect(window.sleepLookback.end == Fixture.instant(hour: 12))
    }

    @Test("every metric declares an aggregation and a unit")
    func metricMapIsComplete() {
        #expect(HealthMetric.allCases.count == 18)
        #expect(HealthMetric.allCases.allSatisfy { $0.unitLabel.isEmpty == false })
        #expect(HealthMetric.backgroundDelivered.allSatisfy { $0.wantsBackgroundDelivery })
        #expect(HealthMetric.heartRate.aggregation == .series)
        #expect(HealthMetric.steps.aggregation == .cumulativeTotal)
        #expect(HealthMetric.bodyMass.aggregation == .mostRecent)
        #expect(HealthMetric.restingHeartRate.aggregation == .dailyAverage)
    }
}
