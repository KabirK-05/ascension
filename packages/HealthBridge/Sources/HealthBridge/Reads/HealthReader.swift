import AscensionCore
import Foundation

/// Reads the spec §6 map and assembles it into the contract's day shapes.
public struct HealthReader: Sendable {
    private let store: any HealthStore
    public let timeZone: TimeZone
    public let zones: HeartRateZones?

    public init(store: any HealthStore,
                timeZone: TimeZone = HealthReader.defaultTimeZone,
                zones: HeartRateZones? = nil) {
        self.store = store
        self.timeZone = timeZone
        self.zones = zones
    }

    /// The user's timezone from the seed contract, falling back to the device's.
    public static var defaultTimeZone: TimeZone {
        TimeZone(identifier: Seed.timezone) ?? .current
    }

    /// One metric over one window, with the uncertainty preserved.
    public func reading(_ metric: HealthMetric,
                        in interval: DateInterval) async -> MetricReading<Double> {
        guard store.isHealthDataAvailable else { return .missing(.healthDataUnavailable) }
        do {
            switch metric.aggregation {
            case .categoryCount:
                let samples = try await store.categorySamples(metric, in: interval)
                return .from(MetricAggregator.standHours(samples).map(Double.init))
            case .categoryIntervals, .workoutRecords:
                return .missing(.queryFailed("\(metric.rawValue) is not a single number"))
            default:
                return .from(try await store.statistic(metric, in: interval))
            }
        } catch let error as HealthStoreError {
            return .missing(gap(for: error))
        } catch {
            return .missing(.queryFailed(String(describing: error)))
        }
    }

    /// Mirrors for an arbitrary window — the backfill path, and what an observer pass
    /// calls after a workout lands.
    public func mirrors(in interval: DateInterval) async throws -> MirrorSet {
        let workoutRecords = try await store.workouts(in: interval)
        var series: [UUID: [QuantityRecord]] = [:]
        for record in workoutRecords {
            series[record.id] = try await store.heartRateSeries(forWorkout: record.id,
                                                               in: record.interval)
        }
        let sleepRecords = try await store.categorySamples(.sleepAnalysis, in: interval)
        let weightRecords = try await store.quantitySamples(.bodyMass, in: interval)
        return MirrorSet(
            workouts: WorkoutMirrorBuilder.mirrors(from: workoutRecords,
                                                   heartRateSeries: series,
                                                   zones: zones),
            nights: SleepNightBuilder.nights(from: sleepRecords, timeZone: timeZone),
            weights: WeightPointBuilder.points(from: weightRecords, timeZone: timeZone))
    }

    /// The whole day, assembled. Never throws: a day the user denied half of is still a
    /// day the app has to render, so failures land in `gaps`.
    public func snapshot(for date: CalendarDate) async -> DayHealthSnapshot {
        guard let window = DayWindow(date: date, timeZone: timeZone) else {
            return DayHealthSnapshot(date: date, timezone: timeZone.identifier,
                                     gaps: [.workouts: .queryFailed("invalid calendar date")])
        }
        var gaps: [HealthMetric: ReadingGap] = [:]
        var values: [HealthMetric: Double] = [:]
        for metric in Self.dailyNumbers {
            switch await reading(metric, in: window.interval) {
            case .measured(let value): values[metric] = value
            case .missing(let gap): gaps[metric] = gap
            }
        }
        return await assemble(window: window, values: values, gaps: gaps)
    }

    /// The metrics that collapse to one number per day. Heart rate is absent on purpose:
    /// a day's average heart rate is not a number this app uses — heart rate matters
    /// inside a workout, as time-in-zone.
    static let dailyNumbers: [HealthMetric] = [
        .steps, .activeEnergy, .restingEnergy, .exerciseMinutes, .standHours,
        .restingHeartRate, .hrvSdnn, .vo2Max, .respiratoryRate, .oxygenSaturation,
        .bodyMass, .bodyFatPercentage, .waistCircumference, .dietaryWater
    ]

    private func assemble(window: DayWindow,
                          values: [HealthMetric: Double],
                          gaps: [HealthMetric: ReadingGap]) async -> DayHealthSnapshot {
        var gaps = gaps
        var snapshot = DayHealthSnapshot(
            date: window.date,
            timezone: timeZone.identifier,
            activity: ActivityRollup(
                steps: values[.steps].map { Int($0.rounded()) },
                activeEnergyKcal: values[.activeEnergy],
                exerciseMinutes: values[.exerciseMinutes].map { Int($0.rounded()) },
                standHours: values[.standHours].map { Int($0.rounded()) }),
            vitals: VitalsRollup(
                restingHrBpm: values[.restingHeartRate].map { Int($0.rounded()) },
                hrvSdnnMs: values[.hrvSdnn],
                vo2Max: values[.vo2Max],
                respiratoryRate: values[.respiratoryRate],
                spo2Pct: values[.oxygenSaturation]),
            body: BodyRollup(weightKg: values[.bodyMass],
                             bodyFatPct: values[.bodyFatPercentage],
                             waistCm: values[.waistCircumference]),
            waterMl: values[.dietaryWater],
            gaps: gaps)

        do {
            let dayMirrors = try await mirrors(in: window.interval)
            snapshot.workouts = dayMirrors.workouts
            snapshot.weight = dayMirrors.weights.last
        } catch {
            gaps[.workouts] = gap(for: error)
            snapshot.gaps = gaps
        }
        await attachSleep(to: &snapshot, window: window, gaps: &gaps)
        snapshot.gaps = gaps
        return snapshot
    }

    private func attachSleep(to snapshot: inout DayHealthSnapshot,
                             window: DayWindow,
                             gaps: inout [HealthMetric: ReadingGap]) async {
        do {
            let records = try await store.categorySamples(.sleepAnalysis, in: window.sleepLookback)
            let nights = SleepNightBuilder.nights(from: records, timeZone: timeZone)
            guard let night = nights.last(where: { $0.date == window.date }) else {
                gaps[.sleepAnalysis] = .noDataOrNoPermission
                return
            }
            snapshot.night = night
            snapshot.sleep = night.rollup
        } catch {
            gaps[.sleepAnalysis] = gap(for: error)
        }
    }

    private func gap(for error: any Error) -> ReadingGap {
        guard let storeError = error as? HealthStoreError else {
            return .queryFailed(String(describing: error))
        }
        switch storeError {
        case .healthDataUnavailable: return .healthDataUnavailable
        case .queryFailed(let detail): return .queryFailed(detail)
        case .unsupportedQuery(let metric): return .queryFailed("unsupported: \(metric.rawValue)")
        case .writeNotAuthorized(let metric): return .queryFailed("write denied: \(metric.rawValue)")
        }
    }
}
