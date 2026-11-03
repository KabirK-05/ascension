import Foundation
import Observation

/// Loads a ``TodaySnapshot`` and holds the presentation the screen draws.
///
/// The mapping itself lives in ``TodayPresenter`` and is pure; this type exists only to
/// own the async edge and the three states a load can be in.
@MainActor
@Observable
public final class TodayModel {

    public enum State: Sendable {
        case loading
        case ready(TodayPresentation)
        case failed
    }

    public private(set) var state: State = .loading

    private let dataSource: any TodayDataSource

    public init(dataSource: any TodayDataSource) {
        self.dataSource = dataSource
    }

    /// Reloads from the data source. A failure is a state, not an alert: the screen
    /// offers a control to try again rather than a paragraph explaining itself (§1.4).
    public func load() async {
        do {
            let snapshot = try await dataSource.snapshot()
            state = .ready(TodayPresenter.present(snapshot))
        } catch {
            state = .failed
        }
    }
}
