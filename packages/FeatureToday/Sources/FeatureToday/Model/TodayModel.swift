import AscensionCore
import Foundation
import Observation

/// Loads a ``TodaySnapshot``, holds the presentation the screen draws, and owns the
/// morning check-in being filled in on top of it.
///
/// The mapping itself lives in ``TodayPresenter`` and is pure; this type exists only to
/// own the async edges — the load and the check-in's save — and the states they can be
/// in. Every tap re-presents from the snapshot, so the screen is never holding a view
/// state the presenter did not derive.
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
    private let checkInStore: (any CheckInStore)?
    private var snapshot: TodaySnapshot?
    private var checkIn = CheckInState()

    public init(dataSource: any TodayDataSource, checkInStore: (any CheckInStore)? = nil) {
        self.dataSource = dataSource
        self.checkInStore = checkInStore
    }

    /// Reloads from the data source. A failure is a state, not an alert: the screen
    /// offers a control to try again rather than a paragraph explaining itself (§1.4).
    public func load() async {
        do {
            let loaded = try await dataSource.snapshot()
            snapshot = loaded
            // A day that already carries a check-in has no controls to hold a draft for,
            // unless the user has opened it again to change an answer — a refresh is not
            // a reason to throw their edit away. A day with no check-in keeps whatever is
            // half-tapped, but never an amendment to some other day's.
            if loaded.today.checkIn == nil {
                if checkIn.isReopened { checkIn = CheckInState() }
            } else if !checkIn.isReopened {
                checkIn = CheckInState()
            }
            present()
        } catch {
            snapshot = nil
            state = .failed
        }
    }

    // MARK: - The check-in (spec §F4)

    /// Opens today's finished check-in to change it, or closes it again.
    ///
    /// Reopening prefills the draft from what was already answered, so this is an
    /// amendment rather than a second blank form. Closing without tapping an energy
    /// discards the draft and leaves the stored check-in exactly as it was, which is
    /// what a disclosure that can be shut again has to mean.
    public func toggleCheckIn() {
        guard let existing = snapshot?.today.checkIn, checkIn.status != .saving else { return }
        checkIn = checkIn.isReopened ? CheckInState() : .reopening(existing)
        present()
    }

    /// One tap on a muscle group: `none` → `mild` → `sore` → `none`.
    public func cycleSoreness(_ group: MuscleGroup) {
        guard checkIn.status != .saving else { return }
        checkIn.draft.cycle(group)
        // Editing after a failure is a fresh attempt, so the retry control goes.
        if checkIn.status == .failed { checkIn.status = .editing }
        present()
    }

    /// Commits the check-in, first time or amended. Tapping an energy is the whole
    /// submission, which is what makes a morning with nothing sore a single tap.
    ///
    /// The snapshot is updated only once the save has returned, so the score never
    /// moves on a write that did not happen. The store is keyed by date, so an
    /// amendment replaces the day's check-in rather than adding a second one.
    public func submitCheckIn(energy: Int) async {
        let isAmendment = checkIn.isReopened
        guard let snapshot,
              snapshot.today.checkIn == nil || isAmendment,
              checkIn.status != .saving,
              let rollup = checkIn.draft.rollup(energy: energy) else { return }

        checkIn.energy = energy
        checkIn.status = .saving
        present()

        do {
            try await checkInStore?.save(rollup, on: snapshot.clock.today)
            // A reload may have landed while the save was in flight, so the check-in
            // goes onto whatever snapshot is current. A first check-in never overwrites
            // one that arrived with that reload; an amendment is meant to.
            if var current = self.snapshot {
                if isAmendment || current.today.checkIn == nil {
                    current.today.checkIn = rollup
                }
                self.snapshot = current
            }
            checkIn = CheckInState()
        } catch {
            checkIn.status = .failed
        }
        present()
    }

    /// Re-submits the energy the failed save was carrying.
    public func retryCheckIn() async {
        guard checkIn.status == .failed, let energy = checkIn.energy else { return }
        checkIn.status = .editing
        await submitCheckIn(energy: energy)
    }

    private func present() {
        guard let snapshot else { return }
        state = .ready(TodayPresenter.present(snapshot, checkIn: checkIn))
    }
}
