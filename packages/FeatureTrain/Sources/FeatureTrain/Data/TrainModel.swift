import AscensionCore
import AscensionEngines
import Foundation
import Observation

/// What Train knows, assembled once per appearance.
///
/// The screen asks one question — am I on program? — so the model computes exactly the
/// answers to it: the week, the adherence behind it, the next session with its loads, and
/// the last session's debrief. Everything here is derived; nothing is a second copy of
/// HealthKit's truth (spec §1).
@MainActor
@Observable
public final class TrainModel {
    public private(set) var program: ProgramDocument = Seed.program
    /// Monday to Sunday of the current week.
    public private(set) var week: [TrainingDay] = []
    public private(set) var adherence = WeekAdherence()
    public private(set) var streak = 0
    public private(set) var next: TrainingDay?
    public private(set) var last: TrainingDay?
    public private(set) var targets: [ProgressionTarget] = []
    public private(set) var isLoaded = false

    /// How far back the streak and the previous-session comparison may reach.
    private static let historyWeeks = 6

    private let environment: TrainEnvironment
    private var history: [TrainingDay] = []
    private var recentSessions: [CompletedSession] = []
    private var recentTopSets: [LoggedTopSet] = []

    public init(environment: TrainEnvironment = .unwired) {
        self.environment = environment
    }

    public var timeZone: TimeZone { environment.timeZone }
    public var canSendToWatch: Bool { environment.sendToWatch != nil }

    public func name(ofExercise id: String) -> String { environment.exerciseName(id) }

    public func load() async {
        let program = await environment.program()
        let today = TrainDay.of(environment.now(), timeZone: environment.timeZone)
        let thisWeek = TrainDay.week(containing: today)
        let days = window(endingWith: thisWeek)
        guard let interval = TrainDay.interval(covering: days, timeZone: environment.timeZone) else {
            return
        }
        let sessions = await environment.sessions(interval)
        let blocks = await environment.blocks(interval)
        let topSets = await environment.topSets(interval)

        let matched = SessionMatcher.days(days, program: program, today: today,
                                          sessions: sessions, blocks: blocks,
                                          timeZone: environment.timeZone)
        apply(program: program, today: today, matched: matched,
              sessions: sessions, topSets: topSets)
    }

    private func apply(program: ProgramDocument, today: CalendarDate,
                       matched: [TrainingDay], sessions: [CompletedSession],
                       topSets: [LoggedTopSet]) {
        let weekDates = Set(TrainDay.week(containing: today).map(\.rawValue))
        self.program = program
        self.history = matched
        self.recentSessions = sessions
        self.recentTopSets = topSets
        self.week = matched.filter { weekDates.contains($0.date.rawValue) }
        self.adherence = Adherence.week(week)
        self.streak = Adherence.streak(matched)
        self.next = matched.first { $0.date >= today && $0.outcome == .upcoming }
        self.last = matched.last { $0.completedBy != nil }
        self.targets = nextTargets()
        self.isLoaded = true
    }

    /// Six whole weeks ending with the current one, plus the week ahead.
    ///
    /// Behind, so a streak has somewhere to run back to and the debrief can find the
    /// previous session of the same type. Ahead, so a Sunday with the week's work done
    /// still has a next session to show.
    private func window(endingWith thisWeek: [CalendarDate]) -> [CalendarDate] {
        guard let monday = thisWeek.first, let sunday = thisWeek.last else { return thisWeek }
        let start = monday.adding(days: -7 * (Self.historyWeeks - 1))
        let end = sunday.adding(days: ProgramDocument.weekdayCount)
        let count = start.days(until: end) + 1
        return (0..<max(1, count)).map { start.adding(days: $0) }
    }

    private func nextTargets() -> [ProgressionTarget] {
        guard let next, let template = program.sessions[next.planned] else { return [] }
        return Progression.targets(for: template, history: recentTopSets,
                                   settings: program.progression)
    }

    // MARK: - Debrief

    /// The debrief for a completed day: the credited session, its zones, and the last
    /// session of the same type to measure it against.
    public func debrief(for day: TrainingDay) -> SessionDebrief? {
        guard let session = day.completedBy else { return nil }
        return SessionDebrief(
            day: day,
            session: session,
            zones: ZoneAnalysis(session.timeInZones),
            comparison: session.previousOfSameType(in: recentSessions)
                .map { SessionComparison.between(session, and: $0) },
            conditioning: conditioning(in: day, credited: session))
    }

    /// The day's conditioning work: the session itself on a Zone 2 day, and otherwise
    /// the finisher walk, which the matcher left in `extras` because a walk does not
    /// complete a lifting day. Spec §F2 wants Zone 2 verified on cardio, and on this
    /// program the cardio is the finisher.
    private func conditioning(in day: TrainingDay,
                              credited: CompletedSession) -> CompletedSession? {
        if credited.modality == .cardio { return credited }
        return day.extras
            .filter { $0.modality == .cardio }
            .max { $0.durationMinutes < $1.durationMinutes }
    }

    // MARK: - Top-set log

    /// The rows the quick log opens with: every loggable slot of the session, prefilled
    /// from the last time that exercise was logged. Prefilled, because a form that starts
    /// empty is not a twenty-second form.
    public func logDraft(for day: TrainingDay) -> [TopSetDraft] {
        guard let template = program.sessions[day.planned] else { return [] }
        let logged = recentTopSets.filter { $0.date == day.date }
        return Progression.loggableSlots(in: template).map { slot in
            let existing = logged.first { $0.exerciseId == slot.exerciseId }
            let target = Progression.target(for: slot, history: recentTopSets,
                                            settings: program.progression)
            return TopSetDraft(exerciseId: slot.exerciseId,
                               name: environment.exerciseName(slot.exerciseId),
                               weightKg: existing?.weightKg ?? target.targetWeightKg,
                               reps: existing?.reps ?? slot.repsLow,
                               target: target)
        }
    }

    public func save(_ drafts: [TopSetDraft], on date: CalendarDate, kind: SessionKind) async {
        let logs = drafts.compactMap { $0.logged(on: date, kind: kind) }
        guard !logs.isEmpty else { return }
        await environment.saveTopSets(logs)
        await load()
    }

    // MARK: - Send to Watch

    public func sendToWatch(_ day: TrainingDay) async throws {
        guard let send = environment.sendToWatch,
              let template = program.sessions[day.planned] else { return }
        try await send(ScheduledSession(
            kind: day.planned,
            template: template,
            finisher: program.finisher,
            date: day.scheduledStart ?? TrainDay.startOfDay(day.date, timeZone: environment.timeZone)
                .addingTimeInterval(18 * 3_600)))
    }
}

/// A completed session with everything the debrief shows (spec §F2).
public struct SessionDebrief: Hashable, Sendable, Identifiable {
    public var day: TrainingDay
    public var session: CompletedSession
    public var zones: ZoneAnalysis
    public var comparison: SessionComparison?
    /// The day's conditioning work, when it had any.
    public var conditioning: CompletedSession?

    public init(day: TrainingDay, session: CompletedSession, zones: ZoneAnalysis,
                comparison: SessionComparison? = nil, conditioning: CompletedSession? = nil) {
        self.day = day
        self.session = session
        self.zones = zones
        self.comparison = comparison
        self.conditioning = conditioning
    }

    public var id: String { session.id }

    public var conditioningZones: ZoneAnalysis? {
        conditioning.map { ZoneAnalysis($0.timeInZones) }
    }

    /// Spec §F2's Zone 2 verification, and only on conditioning: a lifting session's
    /// heart rate wanders by design, and flagging that would be noise.
    public var conditioningDrifted: Bool {
        conditioningZones?.driftedAboveZone2 ?? false
    }
}

/// One row of the quick log, before it is committed.
public struct TopSetDraft: Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var name: String
    public var weightKg: Double?
    public var reps: Int?
    public var target: ProgressionTarget

    public init(exerciseId: String, name: String, weightKg: Double?, reps: Int?,
                target: ProgressionTarget) {
        self.exerciseId = exerciseId
        self.name = name
        self.weightKg = weightKg
        self.reps = reps
        self.target = target
    }

    public var id: String { exerciseId }

    /// `nil` for a row left blank, which is a set that was not done rather than a set of
    /// zero.
    public func logged(on date: CalendarDate, kind: SessionKind) -> LoggedTopSet? {
        guard let weightKg, let reps, weightKg > 0, reps > 0 else { return nil }
        return LoggedTopSet(date: date, exerciseId: exerciseId, weightKg: weightKg,
                            reps: reps, sessionKind: kind)
    }
}
