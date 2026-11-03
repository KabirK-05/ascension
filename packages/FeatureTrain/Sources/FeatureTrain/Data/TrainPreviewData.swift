import AscensionCore
import AscensionEngines
import Foundation

/// Sample data for previews and screenshots.
///
/// Fixed to one instant so a preview is the same picture every time it is opened, and so
/// the week it shows is a realistic one: four sessions planned, one of them missed, a
/// finisher walk on two of them, and a Zone 2 walk that drifted.
extension TrainEnvironment {
    public static let preview: TrainEnvironment = {
        let timeZone = TrainEnvironment.defaultTimeZone
        let now = TrainPreview.now(timeZone: timeZone)
        let today = TrainDay.of(now, timeZone: timeZone)
        let sessions = TrainPreview.sessions(through: today, timeZone: timeZone)
        let blocks = TrainPreview.blocks(through: today, timeZone: timeZone)
        let topSets = TrainPreview.topSets(through: today)
        return TrainEnvironment(
            program: { Seed.program },
            sessions: { interval in sessions.filter { interval.contains($0.start) } },
            blocks: { interval in blocks.filter { interval.contains($0.start) } },
            topSets: { _ in topSets },
            saveTopSets: { _ in },
            sendToWatch: { _ in },
            timeZone: timeZone,
            now: { now })
    }()
}

enum TrainPreview {
    /// A Friday evening, four weeks into the block.
    static func now(timeZone: TimeZone) -> Date {
        TrainDay.startOfDay(CalendarDate.literal("2026-11-27"), timeZone: timeZone)
            .addingTimeInterval(19 * 3_600)
    }

    /// Every lifting day of the last four weeks except one, plus the finisher walks.
    static func sessions(through today: CalendarDate, timeZone: TimeZone) -> [CompletedSession] {
        let program = Seed.program
        let start = today.adding(days: -27)
        var sessions: [CompletedSession] = []
        for offset in 0...start.days(until: today) {
            let date = start.adding(days: offset)
            guard let kind = program.kind(forWeekday: date.isoWeekday), kind.isTrainingDay,
                  let template = program.sessions[kind] else { continue }
            // One deliberate gap: this week's Thursday, so the week reads 2 of 3 so far.
            let missed = date == today.adding(days: -1)
            guard !missed else { continue }
            let begins = TrainDay.startOfDay(date, timeZone: timeZone)
                .addingTimeInterval(18 * 3_600)
            sessions.append(lift(on: date, at: begins, index: offset))
            if template.exercises.contains(where: \.finisher) {
                sessions.append(walk(on: date, at: begins.addingTimeInterval(3_600), index: offset))
            }
        }
        return sessions
    }

    private static func lift(on date: CalendarDate, at start: Date, index: Int) -> CompletedSession {
        let minutes = 46 + index % 7
        return CompletedSession(
            id: "lift-\(date.rawValue)",
            activityType: "traditionalStrengthTraining",
            start: start,
            end: start.addingTimeInterval(Double(minutes) * 60),
            durationMinutes: minutes,
            activeEnergyKcal: Double(280 + index % 9 * 11),
            hrAvgBpm: 118 + index % 5,
            hrMaxBpm: 154 + index % 8,
            timeInZones: TimeInZonesMinutes(z1: Double(minutes) * 0.3, z2: Double(minutes) * 0.45,
                                            z3: Double(minutes) * 0.2, z4: Double(minutes) * 0.05))
    }

    /// The incline-walk finisher. The most recent one drifted out of Zone 2, which is the
    /// case spec §F2 asks the debrief to catch.
    private static func walk(on date: CalendarDate, at start: Date, index: Int) -> CompletedSession {
        let drifted = index % 4 == 3
        return CompletedSession(
            id: "walk-\(date.rawValue)",
            activityType: "walking",
            start: start,
            end: start.addingTimeInterval(15 * 60),
            durationMinutes: 15,
            activeEnergyKcal: Double(92 + index % 5 * 3),
            hrAvgBpm: drifted ? 142 : 128,
            hrMaxBpm: drifted ? 158 : 137,
            timeInZones: drifted
                ? TimeInZonesMinutes(z1: 1, z2: 4.5, z3: 8.5, z4: 1)
                : TimeInZonesMinutes(z1: 2, z2: 11.5, z3: 1.5))
    }

    static func blocks(through today: CalendarDate, timeZone: TimeZone) -> [TrainingBlock] {
        let program = Seed.program
        let start = today.adding(days: -27)
        return (0...start.days(until: today.adding(days: 7))).compactMap { offset in
            let date = start.adding(days: offset)
            guard let kind = program.kind(forWeekday: date.isoWeekday), kind.isTrainingDay,
                  let template = program.sessions[kind] else { return nil }
            let begins = TrainDay.startOfDay(date, timeZone: timeZone)
                .addingTimeInterval(18 * 3_600)
            return TrainingBlock(id: "block-\(date.rawValue)", title: template.name,
                                 start: begins, end: begins.addingTimeInterval(4_500))
        }
    }

    /// The last top set logged for each program exercise, a week back.
    static func topSets(through today: CalendarDate) -> [LoggedTopSet] {
        let week = today.adding(days: -7)
        return [
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.dbBenchPress, weightKg: 20, reps: 11),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.latPulldown, weightKg: 45, reps: 10),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.overheadDbPress, weightKg: 12.5, reps: 12),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.seatedCableRow, weightKg: 40, reps: 12),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.legPress, weightKg: 100, reps: 12),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.hipThrust, weightKg: 60, reps: 10),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.lyingLegCurl, weightKg: 35, reps: 11),
            LoggedTopSet(date: week, exerciseId: SeedExerciseId.walkingLunge, weightKg: 16, reps: 12)
        ]
    }
}
