import AscensionCore
import Foundation

/// One logged meal, as the Eat screen and an applied `log_meal` both record it.
///
/// `id` is the idempotency key all the way through: a meal that came from Muse carries the
/// mutation's ULID, which is also the HealthKit sync identifier, so the same mutation
/// applied twice totals once here and writes once there.
public struct LoggedMeal: Hashable, Sendable, Identifiable {
    public var id: String
    public var slot: MealKind
    public var loggedAt: Timestamp
    public var kcal: Double?
    public var proteinG: Double?
    public var fatG: Double?
    public var carbsG: Double?
    public var waterMl: Double?

    public init(id: String, slot: MealKind, loggedAt: Timestamp, kcal: Double? = nil,
                proteinG: Double? = nil, fatG: Double? = nil, carbsG: Double? = nil,
                waterMl: Double? = nil) {
        self.id = id
        self.slot = slot
        self.loggedAt = loggedAt
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.waterMl = waterMl
    }
}

/// The three rolling numbers the engines own and HealthKit cannot supply
/// (`ASC-5-healthbridge-api.md`: the mirror stops at per-day points).
///
/// Passed in rather than computed, because `AscensionEngines` is not a dependency of this
/// package and the contract's own numbers must not be derived twice.
public struct TrendOverlay: Hashable, Sendable {
    public var weightAvg7Kg: Double?
    public var rateKgPerWeek: Double?
    public var consistencySd7Minutes: Double?

    public init(weightAvg7Kg: Double? = nil, rateKgPerWeek: Double? = nil,
                consistencySd7Minutes: Double? = nil) {
        self.weightAvg7Kg = weightAvg7Kg
        self.rateKgPerWeek = rateKgPerWeek
        self.consistencySd7Minutes = consistencySd7Minutes
    }
}

/// The half of a `DayRollup` the device owns: what was logged, planned, felt and scored.
///
/// HealthKit owns the other half — activity, sleep, vitals, body, workouts, `loadAu` and
/// mirrored water — and `HealthBridge`'s `snapshot.applied(to:)` has already written it
/// into the rollup this overlays.
public struct DeviceDay: Hashable, Sendable {
    public var meals: [LoggedMeal]
    public var sessionPlanned: SessionKind?
    public var sessionDone: Bool
    public var topSets: [TopSet]
    public var checkIn: CheckInRollup?
    public var readiness: ReadinessRollup?
    public var trends: TrendOverlay

    public init(meals: [LoggedMeal] = [], sessionPlanned: SessionKind? = nil,
                sessionDone: Bool = false, topSets: [TopSet] = [],
                checkIn: CheckInRollup? = nil, readiness: ReadinessRollup? = nil,
                trends: TrendOverlay = TrendOverlay()) {
        self.meals = meals
        self.sessionPlanned = sessionPlanned
        self.sessionDone = sessionDone
        self.topSets = topSets
        self.checkIn = checkIn
        self.readiness = readiness
        self.trends = trends
    }

    /// The day's macro totals. A macro no meal carries stays `nil` — *not measured* — and
    /// never collapses to zero, which the contract treats as a measurement of zero.
    public var nutritionTotals: NutritionRollup {
        NutritionRollup(kcal: total(\.kcal),
                        proteinG: total(\.proteinG),
                        fatG: total(\.fatG),
                        carbsG: total(\.carbsG),
                        waterMl: total(\.waterMl))
    }

    private func total(_ field: KeyPath<LoggedMeal, Double?>) -> Double? {
        let values = meals.compactMap { $0[keyPath: field] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}
