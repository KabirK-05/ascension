import AscensionCore
import Foundation

@testable import FeatureTrain

enum Fixture {
    static let timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
    static let program = Seed.program

    /// 2026-11-02 is a Monday, so the week runs Upper A, Lower A, rest, Upper B,
    /// Lower B, rest, rest — the seeded program's own shape.
    static let monday = CalendarDate.literal("2026-11-02")

    static func week() -> [CalendarDate] { TrainDay.week(containing: monday) }

    static func date(_ raw: String) -> CalendarDate { CalendarDate.literal(raw) }

    static func moment(_ day: CalendarDate, hour: Int, minute: Int = 0) -> Date {
        TrainDay.startOfDay(day, timeZone: timeZone)
            .addingTimeInterval(Double(hour) * 3_600 + Double(minute) * 60)
    }

    static func session(_ id: String, type: String = "traditionalStrengthTraining",
                        on day: CalendarDate, hour: Int, minutes: Int = 50,
                        energy: Double? = 300, hrAvg: Int? = 120, hrMax: Int? = 155,
                        zones: TimeInZonesMinutes = TimeInZonesMinutes()) -> CompletedSession {
        let start = moment(day, hour: hour)
        return CompletedSession(id: id, activityType: type, start: start,
                                end: start.addingTimeInterval(Double(minutes) * 60),
                                durationMinutes: minutes, activeEnergyKcal: energy,
                                hrAvgBpm: hrAvg, hrMaxBpm: hrMax, timeInZones: zones)
    }

    static func block(_ id: String, on day: CalendarDate, hour: Int,
                      minutes: Int = 75) -> TrainingBlock {
        let start = moment(day, hour: hour)
        return TrainingBlock(id: id, title: "Session", start: start,
                             end: start.addingTimeInterval(Double(minutes) * 60))
    }

    static func match(_ days: [CalendarDate], today: CalendarDate,
                      sessions: [CompletedSession] = [],
                      blocks: [TrainingBlock] = []) -> [TrainingDay] {
        SessionMatcher.days(days, program: program, today: today, sessions: sessions,
                            blocks: blocks, timeZone: timeZone)
    }
}
