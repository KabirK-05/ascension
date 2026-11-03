import Foundation

/// One day of everything, and the unit of sync (`docs/EXPORT_SCHEMA.md` §1).
///
/// Upserted on `date`, so re-sending a day is always safe. `wins` is computed on device
/// and stored, never recomputed downstream, so the consistency grid cannot disagree with
/// itself across clients.
public struct DayRollup: Codable, Hashable, Sendable {
    public var date: CalendarDate
    public var timezone: String
    public var updatedAt: Timestamp
    public var nutrition: NutritionRollup
    public var activity: ActivityRollup
    public var sleep: SleepRollup
    public var vitals: VitalsRollup
    public var body: BodyRollup
    public var training: TrainingRollup
    public var checkIn: CheckInRollup?
    public var readiness: ReadinessRollup?
    public var wins: Wins

    public init(date: CalendarDate, timezone: String, updatedAt: Timestamp,
                nutrition: NutritionRollup = NutritionRollup(),
                activity: ActivityRollup = ActivityRollup(),
                sleep: SleepRollup = SleepRollup(),
                vitals: VitalsRollup = VitalsRollup(),
                body: BodyRollup = BodyRollup(),
                training: TrainingRollup = TrainingRollup(),
                checkIn: CheckInRollup? = nil,
                readiness: ReadinessRollup? = nil,
                wins: Wins) {
        self.date = date
        self.timezone = timezone
        self.updatedAt = updatedAt
        self.nutrition = nutrition
        self.activity = activity
        self.sleep = sleep
        self.vitals = vitals
        self.body = body
        self.training = training
        self.checkIn = checkIn
        self.readiness = readiness
        self.wins = wins
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(nutrition, forKey: .nutrition)
        try container.encode(activity, forKey: .activity)
        try container.encode(sleep, forKey: .sleep)
        try container.encode(vitals, forKey: .vitals)
        try container.encode(body, forKey: .body)
        try container.encode(training, forKey: .training)
        try container.encodeNullable(checkIn, forKey: .checkIn)
        try container.encodeNullable(readiness, forKey: .readiness)
        try container.encode(wins, forKey: .wins)
    }
}
