import Foundation

@testable import AscensionCore

enum Fixture {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    /// The result of encoding, decoding and re-encoding a value, so a test can assert
    /// that both the value and its bytes survive the trip.
    struct RoundTrip<T: Codable & Equatable> {
        let value: T
        let first: Data
        let second: Data

        /// True when the second encoding is byte-for-byte the first.
        var isStable: Bool { first == second }
    }

    static func roundTrip<T: Codable & Equatable>(_ value: T) throws -> RoundTrip<T> {
        let first = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: first)
        return RoundTrip(value: decoded, first: first, second: try encoder.encode(decoded))
    }

    static func json(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw FixtureError.notAnObject
        }
        return dictionary
    }

    enum FixtureError: Error {
        case notAnObject
    }

    /// The §1 example from `docs/EXPORT_SCHEMA.md`, verbatim.
    static let dayRollupJSON = """
    {
      "date": "2026-11-03",
      "timezone": "America/Toronto",
      "updatedAt": "2026-11-03T23:05:00-05:00",
      "nutrition": { "kcal": 2180, "proteinG": 148, "fatG": 64, "carbsG": 248, "waterMl": 2400 },
      "activity":  { "steps": 10240, "activeEnergyKcal": 612, "exerciseMinutes": 54, "standHours": 10 },
      "sleep":     { "asleepMinutes": 462, "inBedMinutes": 495, "consistencySd7Minutes": 34 },
      "vitals":    { "restingHrBpm": 58, "hrvSdnnMs": 41, "vo2Max": 44.2,
                     "respiratoryRate": 14.1, "spo2Pct": 97 },
      "body":      { "weightKg": 73.6, "weightAvg7Kg": 73.9, "rateKgPerWeek": -0.4,
                     "bodyFatPct": null, "waistCm": null },
      "training": {
        "sessionPlanned": "upperA",
        "sessionDone": true,
        "loadAu": 6120,
        "workouts": [{
          "healthKitId": "A1B2C3D4-0000-0000-0000-000000000001",
          "type": "traditionalStrengthTraining",
          "startedAt": "2026-11-03T19:04:00-05:00",
          "endedAt":   "2026-11-03T19:55:00-05:00",
          "durationMinutes": 51,
          "activeEnergyKcal": 368,
          "hrAvgBpm": 120,
          "hrMaxBpm": 150,
          "timeInZonesMinutes": { "z1": 4, "z2": 22, "z3": 18, "z4": 6, "z5": 1 },
          "source": "Apple Workout"
        }],
        "topSets": [
          { "exerciseId": "Goblet_Squat", "weightKg": 24.0, "reps": 12 },
          { "exerciseId": "DB_Bench_Press", "weightKg": 20.0, "reps": 11 }
        ]
      },
      "checkIn": {
        "energy": 4,
        "soreness": { "chest": "none", "back": "mild", "shoulders": "none",
                      "arms": "none", "quads": "sore", "hamstrings": "mild",
                      "glutes": "none", "core": "none" }
      },
      "readiness": {
        "score": 82,
        "verdict": "trainAsPlanned",
        "reasons": ["slept 7h42", "HRV near baseline"]
      },
      "wins": { "session": true, "protein": true, "steps": true, "sleep": true, "total": 4 }
    }
    """

    static func rollup(
        nutrition: NutritionRollup = NutritionRollup(),
        activity: ActivityRollup = ActivityRollup(),
        sleep: SleepRollup = SleepRollup(),
        training: TrainingRollup = TrainingRollup()
    ) -> DayRollup {
        DayRollup(date: CalendarDate.literal("2026-11-09"),
                  timezone: Seed.timezone,
                  updatedAt: Timestamp.literal("2026-11-09T23:00:00-05:00"),
                  nutrition: nutrition,
                  activity: activity,
                  sleep: sleep,
                  training: training,
                  wins: Wins(session: false, protein: false, steps: false, sleep: false))
    }
}
