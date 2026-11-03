import AscensionCore
import Foundation

@testable import HealthBridge

/// Deterministic fixtures. Every UUID is derived from a string so a test can name the
/// same sample twice and get the same id — which is the whole point of the idempotency
/// tests.
enum Fixture {
    static let timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt

    static func id(_ seed: String) -> UUID {
        var bytes = Array(seed.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// An instant on 2026-11-03 in the user's timezone.
    static func instant(hour: Int, minute: Int = 0, day: Int = 3, month: Int = 11) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func date(_ raw: String) -> CalendarDate {
        CalendarDate(rawValue: raw) ?? CalendarDate.literal("2026-11-03")
    }

    static func quantity(_ seed: String, metric: HealthMetric, value: Double,
                         start: Date, end: Date? = nil,
                         source: String = "Apple Watch") -> QuantityRecord {
        QuantityRecord(id: id(seed), metric: metric, value: value, start: start,
                       end: end ?? start, sourceName: source)
    }

    static func sleep(_ seed: String, stage: SleepStage, start: Date, end: Date,
                      source: String = "Apple Watch") -> CategoryRecord {
        CategoryRecord(id: id(seed), metric: .sleepAnalysis, value: 0, stage: stage,
                       start: start, end: end, sourceName: source)
    }

    static func standHour(_ seed: String, at start: Date, stood: Bool = true) -> CategoryRecord {
        CategoryRecord(id: id(seed), metric: .standHours, value: stood ? 0 : 1,
                       start: start, end: start.addingTimeInterval(3600),
                       sourceName: "Apple Watch")
    }

    static func workout(_ seed: String, type: String = "traditionalStrengthTraining",
                        start: Date, minutes: Int, energy: Double? = 368) -> WorkoutRecord {
        WorkoutRecord(id: id(seed), activityType: type, start: start,
                      end: start.addingTimeInterval(Double(minutes) * 60),
                      activeEnergyKcal: energy, sourceName: "Apple Workout")
    }

    /// A heart-rate series at a fixed cadence, one `bpm` per step.
    static func heartRateSeries(_ seed: String, from start: Date, bpms: [Double],
                                everySeconds: Double = 30) -> [QuantityRecord] {
        bpms.enumerated().map { index, bpm in
            quantity("\(seed)-\(index)", metric: .heartRate, value: bpm,
                     start: start.addingTimeInterval(Double(index) * everySeconds))
        }
    }

    static var zones: HeartRateZones { HeartRateZones.forAge(25) }
}
