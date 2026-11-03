import AscensionCore
import EventKit
import FeatureTrain
import Foundation
import OSLog

/// Where the matcher's training blocks come from.
///
/// A protocol so that the two callers — the Train tab and the rollup refresh — can be
/// tested without EventKit, and so that "no calendar" is a type rather than an empty array
/// someone has to remember to pass.
protocol TrainingBlockSource: Sendable {
    func blocks(in interval: DateInterval, program: ProgramDocument) async -> [TrainingBlock]
    func blocks(on days: [CalendarDate], program: ProgramDocument,
                timeZone: TimeZone) async -> [TrainingBlock]
}

/// No calendar at all. ASC-10's documented fallback, made explicit: a day with several
/// eligible workouts credits the longest.
struct NoTrainingBlocks: TrainingBlockSource {
    func blocks(in interval: DateInterval, program: ProgramDocument) async -> [TrainingBlock] {
        []
    }

    func blocks(on days: [CalendarDate], program: ProgramDocument,
                timeZone: TimeZone) async -> [TrainingBlock] {
        []
    }
}

/// The user's calendar, as the training blocks `SessionMatcher` reads.
///
/// EventKit lives in the app shell — `FeatureTrain` declares `TrainingBlock` and takes the
/// blocks through a closure precisely so that it never imports this framework — and this
/// is the one place it is touched.
///
/// **A refusal is not an error.** `docs/PLAN.md` ASC-10 already specifies the behaviour
/// with no calendar: a day holding several eligible workouts credits the longest. So a
/// denied or restricted store answers with no blocks and the matcher falls back to exactly
/// that rule, which is why nothing here throws and nothing is shown on a screen.
actor CalendarBlockReader: TrainingBlockSource {
    private let store: EKEventStore
    private let logger = Logger(subsystem: "com.kabirkumar.ascension", category: "calendar")

    /// `nil` until access has been asked for once, then the answer for this launch.
    private var granted: Bool?

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    /// Whether the calendar can be read, asking once per launch.
    ///
    /// Asked lazily on the first read rather than at launch: the system sheet then appears
    /// because the user opened Train, not because the app started, and a user who never
    /// opens Train is never asked at all.
    func hasAccess() async -> Bool {
        if let granted { return granted }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            granted = true
        case .denied, .restricted, .writeOnly:
            granted = false
        default:
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        }
        logger.info("calendar access: \(self.granted == true ? "granted" : "unavailable", privacy: .public)")
        return granted ?? false
    }

    /// The training blocks in `interval`, or none.
    func blocks(in interval: DateInterval, program: ProgramDocument) async -> [TrainingBlock] {
        guard await hasAccess() else { return [] }
        let titles = TrainingBlockFilter.titles(in: program)
        let predicate = store.predicateForEvents(withStart: interval.start,
                                                 end: interval.end,
                                                 calendars: nil)
        return store.events(matching: predicate)
            .filter { TrainingBlockFilter.isBlock(title: $0.title ?? "",
                                                  isAllDay: $0.isAllDay,
                                                  titles: titles) }
            .map {
                TrainingBlock(id: $0.eventIdentifier ?? UUID().uuidString,
                              title: $0.title ?? "",
                              start: $0.startDate,
                              end: $0.endDate)
            }
    }

    /// The blocks covering whole local days, which is the window the rollup refresh asks
    /// in. Returns none when the days do not form an interval.
    func blocks(on days: [CalendarDate], program: ProgramDocument,
                timeZone: TimeZone) async -> [TrainingBlock] {
        guard let interval = TrainDay.interval(covering: days, timeZone: timeZone) else {
            return []
        }
        return await blocks(in: interval, program: program)
    }
}
