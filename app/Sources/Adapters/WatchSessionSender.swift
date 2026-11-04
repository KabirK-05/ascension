import AscensionCore
import FeatureTrain
import Foundation
import HealthBridge

/// Send to Watch, for both tabs.
///
/// The one cross-feature link the architecture left to the shell. Today's session card and
/// Train's next-session card each take an injected closure and neither may import
/// `HealthBridge`, where WorkoutKit lives; this builds the plan and hands it to the
/// scheduler, so both buttons end up at the same place and a session sent twice replaces
/// rather than stacks (`WatchSessionScheduler.schedule` removes this app's earlier plans
/// first).
///
/// The app creates a *plan*, never a session: `HKWorkoutSession` appears nowhere in this
/// repository and must not (spec §1). The Watch Workout app records; this prescribes.
struct WatchSessionSender: Sendable {
    /// The hour a session with no calendar block is scheduled for, matching the default
    /// `FeatureTrain` already picks for its own card.
    static let defaultHour: TimeInterval = 18 * 3_600

    /// How far ahead a session sent *now* is placed when the usual hour has passed, so the
    /// Watch is never handed a workout that started in the past.
    static let minimumLead: TimeInterval = 15 * 60

    private let scheduler: any SessionScheduling
    private let zones: HeartRateZones?

    init(scheduler: any SessionScheduling, zones: HeartRateZones?) {
        self.scheduler = scheduler
        self.zones = zones
    }

    /// Whether there is a Watch to send to. `nil` is what *hides* both buttons rather than
    /// offering one that cannot work, so this is the value the composition root tests.
    var isSupported: Bool { scheduler.isSupported }

    /// Train's seam: the feature has already chosen the session and when it starts.
    func send(_ session: ScheduledSession,
              program: ProgramDocument,
              exerciseNames: [String: String]) async throws {
        try await schedule(kind: session.kind,
                           template: session.template,
                           finisher: session.finisher,
                           at: session.date,
                           exerciseNames: exerciseNames)
    }

    /// Today's seam: the card knows only the kind it is showing — which on a swap is the
    /// swapped-to session, not the planned one — so the template comes from the program.
    func send(kind: SessionKind,
              program: ProgramDocument,
              exerciseNames: [String: String],
              clock: DayClock,
              now: Date = Date()) async throws {
        guard let template = program.sessions[kind] else {
            throw SessionSchedulingError.nothingToSchedule
        }
        try await schedule(kind: kind,
                           template: template,
                           finisher: program.finisher,
                           at: Self.startTime(for: clock.day(of: now), clock: clock, now: now),
                           exerciseNames: exerciseNames)
    }

    private func schedule(kind: SessionKind,
                          template: SessionTemplateEntry,
                          finisher: FinisherSettings,
                          at date: Date,
                          exerciseNames: [String: String]) async throws {
        guard let plan = SessionPlanBuilder.plan(kind: kind, template: template,
                                                 finisher: finisher,
                                                 exerciseNames: exerciseNames,
                                                 zones: zones) else {
            // A rest day, or a session with nothing a Watch can be told to do.
            throw SessionSchedulingError.nothingToSchedule
        }
        try await scheduler.schedule(plan, at: date)
    }

    /// The usual hour today, or a short lead from now once that hour has gone.
    static func startTime(for date: CalendarDate, clock: DayClock, now: Date) -> Date {
        let usual = clock.startOfDay(date).addingTimeInterval(defaultHour)
        return usual > now ? usual : now.addingTimeInterval(minimumLead)
    }
}
