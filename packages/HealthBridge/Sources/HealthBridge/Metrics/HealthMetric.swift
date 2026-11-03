import Foundation

/// Everything this app reads out of HealthKit (spec §6).
///
/// The raw values are stable identifiers, not HealthKit's: the HealthKit type each one
/// maps to lives in the adapter, so the rest of the module — and every test — can name a
/// metric without importing HealthKit.
public enum HealthMetric: String, Codable, Hashable, Sendable, CaseIterable {
    case workouts
    case activeEnergy
    case restingEnergy
    case steps
    case exerciseMinutes
    case standHours
    case heartRate
    case restingHeartRate
    case hrvSdnn
    case vo2Max
    case heartRateRecovery
    case sleepAnalysis
    case respiratoryRate
    case oxygenSaturation
    case bodyMass
    case bodyFatPercentage
    case waistCircumference
    case dietaryWater
}

/// How a metric collapses into one number for a day.
///
/// This is a property of the measurement, not of the caller: steps are a total, resting
/// heart rate is an average of the day's samples, and weight is whatever the scale last
/// said. Getting this wrong silently produces a plausible, wrong number, so it is stated
/// once here and nowhere else.
public enum MetricAggregation: String, Hashable, Sendable {
    /// Sum of every sample in the window (steps, energy, water, exercise minutes).
    case cumulativeTotal
    /// Mean of the day's discrete samples (resting HR, HRV, respiratory rate, SpO2).
    case dailyAverage
    /// The newest sample at or before the end of the window (weight, VO2 max, waist).
    case mostRecent
    /// Every sample, kept as a series (heart rate, for time-in-zone).
    case series
    /// Category samples that are counted, not summed (stand hours).
    case categoryCount
    /// Category samples whose intervals matter (sleep analysis).
    case categoryIntervals
    /// Workouts, which carry their own statistics.
    case workoutRecords
}

extension HealthMetric {
    public var aggregation: MetricAggregation {
        switch self {
        case .activeEnergy, .restingEnergy, .steps, .exerciseMinutes, .dietaryWater:
            return .cumulativeTotal
        case .restingHeartRate, .hrvSdnn, .respiratoryRate, .oxygenSaturation:
            return .dailyAverage
        case .vo2Max, .bodyMass, .bodyFatPercentage, .waistCircumference, .heartRateRecovery:
            return .mostRecent
        case .heartRate:
            return .series
        case .standHours:
            return .categoryCount
        case .sleepAnalysis:
            return .categoryIntervals
        case .workouts:
            return .workoutRecords
        }
    }

    /// The unit every value of this metric is carried in, module-wide. The adapter
    /// converts at the boundary; nothing downstream converts again.
    public var unitLabel: String {
        switch self {
        case .activeEnergy, .restingEnergy: return "kcal"
        case .steps: return "count"
        case .exerciseMinutes: return "min"
        case .standHours: return "hours"
        case .heartRate, .restingHeartRate, .heartRateRecovery: return "bpm"
        case .hrvSdnn: return "ms"
        case .vo2Max: return "ml/kg·min"
        case .respiratoryRate: return "breaths/min"
        case .oxygenSaturation, .bodyFatPercentage: return "%"
        case .bodyMass: return "kg"
        case .waistCircumference: return "cm"
        case .dietaryWater: return "mL"
        case .sleepAnalysis: return "min"
        case .workouts: return "workout"
        }
    }

    /// The metrics spec §6 marks with an asterisk: observer query plus background
    /// delivery, so a workout or a weigh-in lands without the app being opened.
    public static let backgroundDelivered: Set<HealthMetric> = [
        .workouts, .activeEnergy, .restingEnergy, .steps, .heartRate, .sleepAnalysis, .bodyMass
    ]

    public var wantsBackgroundDelivery: Bool { Self.backgroundDelivered.contains(self) }
}

/// The narrow write surface (spec §6: "and nothing else in v1").
///
/// Read is broad because interpretation needs breadth; write is seven types because
/// every one of them is something the user — or Muse on the user's behalf — logged.
public enum HealthWriteMetric: String, Codable, Hashable, Sendable, CaseIterable {
    case dietaryEnergy
    case dietaryProtein
    case dietaryCarbohydrates
    case dietaryFat
    case dietaryWater
    case bodyMass
    case waistCircumference
}

extension HealthWriteMetric {
    public var unitLabel: String {
        switch self {
        case .dietaryEnergy: return "kcal"
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFat: return "g"
        case .dietaryWater: return "mL"
        case .bodyMass: return "kg"
        case .waistCircumference: return "cm"
        }
    }
}

/// The scopes the app asks for, in one place so the authorization sheet and the
/// Info.plist usage strings can never drift apart.
public enum HealthScopes {
    /// Read is the whole §6 map.
    public static let read: Set<HealthMetric> = Set(HealthMetric.allCases)
    /// Write is nutrition, water and the two manual body measurements.
    public static let write: Set<HealthWriteMetric> = Set(HealthWriteMetric.allCases)
}
