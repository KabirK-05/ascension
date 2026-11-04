import Foundation

/// Logged food for the day. `nil` means not measured, never zero.
public struct NutritionRollup: Codable, Hashable, Sendable {
    public var kcal: Double?
    public var proteinG: Double?
    public var fatG: Double?
    public var carbsG: Double?
    public var waterMl: Double?

    public init(kcal: Double? = nil, proteinG: Double? = nil, fatG: Double? = nil,
                carbsG: Double? = nil, waterMl: Double? = nil) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.waterMl = waterMl
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(kcal, forKey: .kcal)
        try container.encodeNullable(proteinG, forKey: .proteinG)
        try container.encodeNullable(fatG, forKey: .fatG)
        try container.encodeNullable(carbsG, forKey: .carbsG)
        try container.encodeNullable(waterMl, forKey: .waterMl)
    }
}

/// Movement for the day, mirrored from HealthKit.
public struct ActivityRollup: Codable, Hashable, Sendable {
    public var steps: Int?
    public var activeEnergyKcal: Double?
    public var exerciseMinutes: Int?
    public var standHours: Int?

    public init(steps: Int? = nil, activeEnergyKcal: Double? = nil,
                exerciseMinutes: Int? = nil, standHours: Int? = nil) {
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(steps, forKey: .steps)
        try container.encodeNullable(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encodeNullable(exerciseMinutes, forKey: .exerciseMinutes)
        try container.encodeNullable(standHours, forKey: .standHours)
    }
}

/// Last night's sleep. `consistencySd7Minutes` is the 7-day bedtime standard deviation.
public struct SleepRollup: Codable, Hashable, Sendable {
    public var asleepMinutes: Int?
    public var inBedMinutes: Int?
    public var consistencySd7Minutes: Double?

    public init(asleepMinutes: Int? = nil, inBedMinutes: Int? = nil,
                consistencySd7Minutes: Double? = nil) {
        self.asleepMinutes = asleepMinutes
        self.inBedMinutes = inBedMinutes
        self.consistencySd7Minutes = consistencySd7Minutes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(asleepMinutes, forKey: .asleepMinutes)
        try container.encodeNullable(inBedMinutes, forKey: .inBedMinutes)
        try container.encodeNullable(consistencySd7Minutes, forKey: .consistencySd7Minutes)
    }
}

/// Resting physiology, mirrored from HealthKit.
public struct VitalsRollup: Codable, Hashable, Sendable {
    public var restingHrBpm: Int?
    public var hrvSdnnMs: Double?
    public var vo2Max: Double?
    public var respiratoryRate: Double?
    public var spo2Pct: Double?

    public init(restingHrBpm: Int? = nil, hrvSdnnMs: Double? = nil, vo2Max: Double? = nil,
                respiratoryRate: Double? = nil, spo2Pct: Double? = nil) {
        self.restingHrBpm = restingHrBpm
        self.hrvSdnnMs = hrvSdnnMs
        self.vo2Max = vo2Max
        self.respiratoryRate = respiratoryRate
        self.spo2Pct = spo2Pct
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(restingHrBpm, forKey: .restingHrBpm)
        try container.encodeNullable(hrvSdnnMs, forKey: .hrvSdnnMs)
        try container.encodeNullable(vo2Max, forKey: .vo2Max)
        try container.encodeNullable(respiratoryRate, forKey: .respiratoryRate)
        try container.encodeNullable(spo2Pct, forKey: .spo2Pct)
    }
}

/// Body composition. `weightAvg7Kg` is the number that matters (spec §F6).
public struct BodyRollup: Codable, Hashable, Sendable {
    public var weightKg: Double?
    public var weightAvg7Kg: Double?
    public var rateKgPerWeek: Double?
    public var bodyFatPct: Double?
    public var waistCm: Double?

    public init(weightKg: Double? = nil, weightAvg7Kg: Double? = nil,
                rateKgPerWeek: Double? = nil, bodyFatPct: Double? = nil,
                waistCm: Double? = nil) {
        self.weightKg = weightKg
        self.weightAvg7Kg = weightAvg7Kg
        self.rateKgPerWeek = rateKgPerWeek
        self.bodyFatPct = bodyFatPct
        self.waistCm = waistCm
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(weightKg, forKey: .weightKg)
        try container.encodeNullable(weightAvg7Kg, forKey: .weightAvg7Kg)
        try container.encodeNullable(rateKgPerWeek, forKey: .rateKgPerWeek)
        try container.encodeNullable(bodyFatPct, forKey: .bodyFatPct)
        try container.encodeNullable(waistCm, forKey: .waistCm)
    }
}
