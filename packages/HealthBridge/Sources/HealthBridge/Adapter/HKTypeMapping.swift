#if canImport(HealthKit)
import HealthKit

// Every function here is one exhaustive switch over `HealthMetric` — a lookup table with
// a case per metric and no branching logic. Cyclomatic complexity counts the cases and
// measures the wrong thing; an exhaustive switch is the point, because adding a metric
// then fails to compile until it is mapped.
// swiftlint:disable cyclomatic_complexity
/// The one place HealthKit identifiers and units are named.
///
/// Everything above this file speaks `HealthMetric` and canonical units, so a unit
/// mistake can only be made once, here, and is caught by a single test per metric.
enum HKTypeMapping {
    static func quantityType(for metric: HealthMetric) -> HKQuantityType? {
        guard let identifier = quantityIdentifier(for: metric) else { return nil }
        return HKQuantityType(identifier)
    }

    static func quantityIdentifier(for metric: HealthMetric) -> HKQuantityTypeIdentifier? {
        switch metric {
        case .activeEnergy: return .activeEnergyBurned
        case .restingEnergy: return .basalEnergyBurned
        case .steps: return .stepCount
        case .exerciseMinutes: return .appleExerciseTime
        case .heartRate: return .heartRate
        case .restingHeartRate: return .restingHeartRate
        case .hrvSdnn: return .heartRateVariabilitySDNN
        case .vo2Max: return .vo2Max
        case .heartRateRecovery: return .heartRateRecoveryOneMinute
        case .respiratoryRate: return .respiratoryRate
        case .oxygenSaturation: return .oxygenSaturation
        case .bodyMass: return .bodyMass
        case .bodyFatPercentage: return .bodyFatPercentage
        case .waistCircumference: return .waistCircumference
        case .dietaryWater: return .dietaryWater
        case .standHours, .sleepAnalysis, .workouts: return nil
        }
    }

    static func categoryType(for metric: HealthMetric) -> HKCategoryType? {
        switch metric {
        case .standHours: return HKCategoryType(.appleStandHour)
        case .sleepAnalysis: return HKCategoryType(.sleepAnalysis)
        default: return nil
        }
    }

    static func sampleType(for metric: HealthMetric) -> HKSampleType? {
        if metric == .workouts { return HKObjectType.workoutType() }
        return quantityType(for: metric) ?? categoryType(for: metric)
    }

    /// The HealthKit unit a metric's canonical value is read in, and the factor that
    /// converts it. Percent types are the only ones that need a factor: HealthKit stores
    /// them as a fraction and the contract carries them as a percentage.
    static func unit(for metric: HealthMetric) -> (unit: HKUnit, scale: Double)? {
        switch metric {
        case .activeEnergy, .restingEnergy: return (.kilocalorie(), 1)
        case .steps: return (.count(), 1)
        case .exerciseMinutes: return (.minute(), 1)
        case .heartRate, .restingHeartRate, .heartRateRecovery, .respiratoryRate:
            return (HKUnit.count().unitDivided(by: .minute()), 1)
        case .hrvSdnn: return (.secondUnit(with: .milli), 1)
        case .vo2Max: return (vo2MaxUnit, 1)
        case .oxygenSaturation, .bodyFatPercentage: return (.percent(), 100)
        case .bodyMass: return (.gramUnit(with: .kilo), 1)
        case .waistCircumference: return (.meterUnit(with: .centi), 1)
        case .dietaryWater: return (.literUnit(with: .milli), 1)
        case .standHours, .sleepAnalysis, .workouts: return nil
        }
    }

    /// ml/(kg·min).
    static var vo2MaxUnit: HKUnit {
        let mass = HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())
        return HKUnit.literUnit(with: .milli).unitDivided(by: mass)
    }

    static func quantityType(for metric: HealthWriteMetric) -> HKQuantityType {
        switch metric {
        case .dietaryEnergy: return HKQuantityType(.dietaryEnergyConsumed)
        case .dietaryProtein: return HKQuantityType(.dietaryProtein)
        case .dietaryCarbohydrates: return HKQuantityType(.dietaryCarbohydrates)
        case .dietaryFat: return HKQuantityType(.dietaryFatTotal)
        case .dietaryWater: return HKQuantityType(.dietaryWater)
        case .bodyMass: return HKQuantityType(.bodyMass)
        case .waistCircumference: return HKQuantityType(.waistCircumference)
        }
    }

    static func unit(for metric: HealthWriteMetric) -> HKUnit {
        switch metric {
        case .dietaryEnergy: return .kilocalorie()
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFat: return .gram()
        case .dietaryWater: return .literUnit(with: .milli)
        case .bodyMass: return .gramUnit(with: .kilo)
        case .waistCircumference: return .meterUnit(with: .centi)
        }
    }

    static func statisticsOptions(for metric: HealthMetric) -> HKStatisticsOptions {
        switch metric.aggregation {
        case .cumulativeTotal: return .cumulativeSum
        case .dailyAverage: return .discreteAverage
        default: return .mostRecent
        }
    }

    static func stage(forSleepValue value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        case .awake: return .awake
        default: return nil
        }
    }

    /// A stable name for the activity type, matching the contract's example spelling.
    /// Unmapped types keep their raw value rather than collapsing to "other", so an
    /// unexpected activity is visible in the export instead of disguised.
    static func activityName(_ type: HKWorkoutActivityType) -> String {
        if let name = activityNames[type] { return name }
        return "activityType\(type.rawValue)"
    }

    private static let activityNames: [HKWorkoutActivityType: String] = [
        .traditionalStrengthTraining: "traditionalStrengthTraining",
        .functionalStrengthTraining: "functionalStrengthTraining",
        .highIntensityIntervalTraining: "highIntensityIntervalTraining",
        .coreTraining: "coreTraining",
        .running: "running",
        .walking: "walking",
        .hiking: "hiking",
        .cycling: "cycling",
        .rowing: "rowing",
        .elliptical: "elliptical",
        .stairClimbing: "stairClimbing",
        .stairs: "stairs",
        .jumpRope: "jumpRope",
        .swimming: "swimming",
        .mixedCardio: "mixedCardio",
        .flexibility: "flexibility",
        .yoga: "yoga",
        .pilates: "pilates",
        .cooldown: "cooldown",
        .preparationAndRecovery: "preparationAndRecovery",
        .other: "other"
    ]
}
// swiftlint:enable cyclomatic_complexity
#endif
