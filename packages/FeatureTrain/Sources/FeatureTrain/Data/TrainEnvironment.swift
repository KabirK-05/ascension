import AscensionCore
import AscensionEngines
import Foundation

/// A session handed to the Watch.
///
/// `FeatureTrain` cannot name `HealthBridge`'s plan types, so it describes the session in
/// the contract's own vocabulary and the app shell builds the WorkoutKit plan from it.
/// That is the seam ASC-9's Send to Watch button also wires through.
public struct ScheduledSession: Hashable, Sendable {
    public var kind: SessionKind
    public var template: SessionTemplateEntry
    public var finisher: FinisherSettings
    public var date: Date

    public init(kind: SessionKind, template: SessionTemplateEntry,
                finisher: FinisherSettings, date: Date) {
        self.kind = kind
        self.template = template
        self.finisher = finisher
        self.date = date
    }
}

/// Everything Train needs from outside itself.
///
/// Closures rather than a protocol zoo: HealthKit, EventKit, WorkoutKit and SwiftData all
/// live in the app shell, and this package stays buildable and testable without any of
/// them (`CLAUDE.md` — a feature depends on Core, Engines and DesignSystem, and on no
/// other feature).
public struct TrainEnvironment: Sendable {
    public var program: @Sendable () async -> ProgramDocument
    public var sessions: @Sendable (DateInterval) async -> [CompletedSession]
    public var blocks: @Sendable (DateInterval) async -> [TrainingBlock]
    public var topSets: @Sendable (DateInterval) async -> [LoggedTopSet]
    public var saveTopSets: @Sendable ([LoggedTopSet]) async -> Void
    /// `nil` where the Watch cannot be reached, which is what hides the control rather
    /// than offering one that cannot work.
    public var sendToWatch: (@Sendable (ScheduledSession) async throws -> Void)?
    public var exerciseName: @Sendable (String) -> String
    public var timeZone: TimeZone
    public var now: @Sendable () -> Date

    public init(
        program: @escaping @Sendable () async -> ProgramDocument = { Seed.program },
        sessions: @escaping @Sendable (DateInterval) async -> [CompletedSession] = { _ in [] },
        blocks: @escaping @Sendable (DateInterval) async -> [TrainingBlock] = { _ in [] },
        topSets: @escaping @Sendable (DateInterval) async -> [LoggedTopSet] = { _ in [] },
        saveTopSets: @escaping @Sendable ([LoggedTopSet]) async -> Void = { _ in },
        sendToWatch: (@Sendable (ScheduledSession) async throws -> Void)? = nil,
        exerciseName: @escaping @Sendable (String) -> String = TrainEnvironment.seededName,
        timeZone: TimeZone = TrainEnvironment.defaultTimeZone,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.program = program
        self.sessions = sessions
        self.blocks = blocks
        self.topSets = topSets
        self.saveTopSets = saveTopSets
        self.sendToWatch = sendToWatch
        self.exerciseName = exerciseName
        self.timeZone = timeZone
        self.now = now
    }

    public static let defaultTimeZone = TimeZone(identifier: Seed.timezone) ?? .gmt

    /// The program's own names. ASC-8's note is explicit that the dataset supplies
    /// instructions and images, and that the name stays the seed's.
    public static let seededName: @Sendable (String) -> String = { id in
        seededNames[id] ?? id
    }

    private static let seededNames: [String: String] = Dictionary(
        Seed.programExercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

    /// The program with nothing read yet: what the app shows before the shell wires
    /// HealthKit and the calendar in.
    public static let unwired = TrainEnvironment()
}

extension TrainDay {
    /// The instants spanned by `days`, in the user's timezone, so a read window covers
    /// whole local days rather than whole UTC ones.
    public static func interval(covering days: [CalendarDate], timeZone: TimeZone) -> DateInterval? {
        guard let first = days.min(), let last = days.max() else { return nil }
        let start = startOfDay(first, timeZone: timeZone)
        let end = startOfDay(last.adding(days: 1), timeZone: timeZone)
        return DateInterval(start: start, end: max(start, end))
    }

    public static func startOfDay(_ date: CalendarDate, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(timeZone: timeZone, year: date.year,
                                   month: date.month, day: date.day)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}
