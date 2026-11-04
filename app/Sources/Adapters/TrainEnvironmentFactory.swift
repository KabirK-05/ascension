import AscensionCore
import AscensionEngines
import FeatureTrain
import Foundation
import HealthBridge

/// Builds `FeatureTrain`'s environment out of HealthKit, the store and the Watch.
///
/// `TrainEnvironment` is closures rather than protocols, so this is where the four
/// frameworks Train is not allowed to import get bound to it. `CompletedSession`'s failable
/// initialiser from a `WorkoutSummary` is the intended bridge — ASC-10 says so explicitly —
/// and the mapping happens here rather than in either package.
enum TrainEnvironmentFactory {
    /// `sendToWatch` is `nil` where WorkoutKit cannot schedule, which **hides** the control
    /// rather than offering one that cannot work. That is `TrainEnvironment`'s own contract
    /// and `TrainModel.canSendToWatch` reads it directly.
    static func environment(bridge: HealthBridgeService,
                            store: LocalStore,
                            watch: WatchSessionSender,
                            calendar: any TrainingBlockSource,
                            timeZone: TimeZone) -> TrainEnvironment {
        let program: @Sendable () async -> ProgramDocument = { await store.program }

        let sessions: @Sendable (DateInterval) async -> [CompletedSession] = { interval in
            await completedSessions(in: interval, bridge: bridge, timeZone: timeZone)
        }

        let blocks: @Sendable (DateInterval) async -> [TrainingBlock] = { interval in
            await calendar.blocks(in: interval, program: await store.program)
        }

        let topSets: @Sendable (DateInterval) async -> [LoggedTopSet] = { interval in
            await store.loggedTopSets(in: dates(in: interval, timeZone: timeZone))
        }

        let saveTopSets: @Sendable ([LoggedTopSet]) async -> Void = { logs in
            await store.save(topSets: logs)
        }

        let scheduleOnWatch: @Sendable (ScheduledSession) async throws -> Void = { session in
            try await watch.send(session,
                                 program: await store.program,
                                 exerciseNames: await store.exerciseNames)
        }
        let send: (@Sendable (ScheduledSession) async throws -> Void)? =
            watch.isSupported ? scheduleOnWatch : nil

        return TrainEnvironment(
            program: program,
            sessions: sessions,
            // The user's calendar, filtered to training blocks. When access is refused
            // this answers with none, and the matcher falls back to ASC-10's documented
            // rule: the longest eligible workout of the day is the one credited.
            blocks: blocks,
            topSets: topSets,
            saveTopSets: saveTopSets,
            sendToWatch: send,
            exerciseName: TrainEnvironment.seededName,
            timeZone: timeZone,
            now: { Date() })
    }

    /// Workouts HealthKit recorded in the window, as the sessions the matcher reads.
    ///
    /// A mirror that cannot be expressed as a `CompletedSession` is dropped rather than
    /// guessed at: `CompletedSession`'s initialiser is failable because a summary with an
    /// unreadable timestamp is not a session anyone can reason about.
    private static func completedSessions(in interval: DateInterval,
                                          bridge: HealthBridgeService,
                                          timeZone: TimeZone) async -> [CompletedSession] {
        guard let mirrors = try? await bridge.mirrors(in: interval) else { return [] }
        return mirrors.workouts.compactMap { CompletedSession($0.summary(timeZone: timeZone)) }
    }

    /// The local days an instant range covers, for the store reads that are keyed by date.
    private static func dates(in interval: DateInterval, timeZone: TimeZone) -> [CalendarDate] {
        let clock = DayClock(timeZone: timeZone)
        let first = clock.day(of: interval.start)
        let last = clock.day(of: interval.end)
        var dates: [CalendarDate] = []
        var cursor = first
        while cursor <= last, dates.count < 400 {
            dates.append(cursor)
            cursor = cursor.adding(days: 1)
        }
        return dates
    }
}
