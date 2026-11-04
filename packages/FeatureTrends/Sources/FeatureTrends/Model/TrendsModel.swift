import AscensionCore
import AscensionEngines
import Foundation
import Observation

/// Accepts a calorie suggestion.
///
/// Spec §F6: targets never change silently, so accepting is a user action and this is the
/// only way one leaves this package. The contract carries it as
/// `accept_suggestion { suggestionId }` (`docs/EXPORT_SCHEMA.md` §3) — the engine never
/// mutates anything itself, and neither does this tab.
public protocol SuggestionAcceptor: Sendable {
    func accept(suggestionId: String) async throws
}

/// Loads a ``TrendsSnapshot``, holds the presentation the tab draws, and owns the one
/// write this tab can make.
///
/// The mapping lives in ``TrendsPresenter`` and is pure; this type exists only for the
/// async edges — the load, the review's text generation, and accepting a suggestion.
@MainActor
@Observable
public final class TrendsModel {

    public enum State: Sendable {
        case loading
        case ready(TrendsPresentation)
        case failed
    }

    /// Where the one-tap accept has got to. Not an alert: the card shows its own state.
    public enum AcceptState: Hashable, Sendable {
        case idle
        case accepting
        case accepted
        case failed
    }

    public private(set) var state: State = .loading
    public private(set) var acceptState: AcceptState = .idle

    private let dataSource: any TrendsDataSource
    private let acceptor: (any SuggestionAcceptor)?
    private let reviewWriter: (any WeeklyReviewWriter)?

    /// - Parameters:
    ///   - reviewWriter: writes the review's two lines. `nil` builds one from the
    ///     snapshot's own flags, which is what the app does; a test passes its own.
    public init(dataSource: any TrendsDataSource,
                acceptor: (any SuggestionAcceptor)? = nil,
                reviewWriter: (any WeeklyReviewWriter)? = nil) {
        self.dataSource = dataSource
        self.acceptor = acceptor
        self.reviewWriter = reviewWriter
    }

    /// Reloads from the data source. A failure is a state, not an alert: the tab offers a
    /// control to try again rather than a paragraph explaining itself (§1.4).
    public func load() async {
        do {
            let snapshot = try await dataSource.snapshot()
            let text = await reviewText(for: snapshot)
            state = .ready(TrendsPresenter.present(snapshot, review: text))
            acceptState = .idle
        } catch {
            state = .failed
        }
    }

    /// Accepts the suggestion and reloads, so the card disappears because the engine no
    /// longer proposes it — never because this type hid it.
    public func accept(suggestionId: String) async {
        guard let acceptor else { return }
        acceptState = .accepting
        do {
            try await acceptor.accept(suggestionId: suggestionId)
            acceptState = .accepted
            await load()
        } catch {
            acceptState = .failed
        }
    }

    /// The review's two lines, when the week has ended on the day the review is for.
    ///
    /// Scheduling the Sunday notification belongs to ASC-16; this is the card, and
    /// ``WeeklyReview/isDue(_:)`` is the entry point that ticket calls.
    private func reviewText(for snapshot: TrendsSnapshot) async -> WeeklyReviewText? {
        guard WeeklyReview.isDue(snapshot.clock.today) else { return nil }
        let writer = reviewWriter ?? FoundationModelsReviewWriter(flags: snapshot.flags)
        return await writer.write(WeeklyReviewFacts(report: snapshot.weeklyReport,
                                                    goals: snapshot.goals))
    }
}

/// When the weekly review exists (spec §F7).
public enum WeeklyReview {
    /// Sunday, ISO-8601 weekday 7.
    public static let reviewWeekday = 7

    /// The review covers one week.
    public static let windowDays = 7

    /// Whether `day` is the day the review covers.
    ///
    /// The *notification* is ASC-16's; this is the only rule about the card itself, and
    /// it reads `CalendarDate.isoWeekday` so no ambient calendar is consulted.
    public static func isDue(_ day: CalendarDate) -> Bool {
        day.isoWeekday == reviewWeekday
    }

    /// The review for a snapshot, whatever day it is.
    ///
    /// The clean entry point ASC-16 schedules against: it ignores ``isDue(_:)``, because
    /// a notification firing on Sunday evening already decided the day.
    public static func text(for snapshot: TrendsSnapshot,
                            writer: (any WeeklyReviewWriter)? = nil) async -> WeeklyReviewText? {
        let writer = writer ?? FoundationModelsReviewWriter(flags: snapshot.flags)
        return await writer.write(WeeklyReviewFacts(report: snapshot.weeklyReport,
                                                    goals: snapshot.goals))
    }
}
