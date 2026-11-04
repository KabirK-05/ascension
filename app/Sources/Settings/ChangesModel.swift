import AscensionCore
import Foundation
import Observation

/// Settings → Changes: the remote writes this device applied, and the undo for the two
/// that are worth reversing.
///
/// `docs/MUSE_CAPABILITIES.md` gives Muse full authority over targets and the program.
/// This is the safety net that makes that reasonable — not a confirmation prompt on every
/// write, which would make the connector useless, but a list after the fact with one tap
/// to put a value back.
@MainActor
@Observable
final class ChangesModel {
    private(set) var rows: [RecordedChange] = []
    private(set) var undoing: String?

    private let composition: AppComposition
    private let now: @Sendable () -> Date

    init(composition: AppComposition, now: @escaping @Sendable () -> Date = { Date() }) {
        self.composition = composition
        self.now = now
    }

    func load() async {
        rows = await composition.changes.all()
    }

    /// Puts a document back to the value it had before this write.
    ///
    /// Restores the **whole** document rather than inverting a patch, and takes the next
    /// version number rather than the old one: the Worker counts versions across every
    /// client, so rewinding the number would be rejected or, worse, accepted and then
    /// collide. The undo is a new write that happens to carry an old body.
    func undo(_ change: RecordedChange) async {
        guard let previous = change.previous, undoing == nil else { return }
        undoing = change.id
        defer { undoing = nil }

        let restored = restore(previous)
        guard restored else { return }
        await composition.changes.markUndone(
            id: change.id, at: Timestamp(now(), timeZone: composition.store.timeZone))
        await load()
    }

    private func restore(_ previous: PreviousDocument) -> Bool {
        let store = composition.store
        let stamp = Timestamp(now(), timeZone: store.timeZone)
        let writer = composition.documentWriter()

        switch previous {
        case .goalSettings(let old):
            var document = old
            document.version = store.goals.version + 1
            document.updatedAt = stamp
            document.updatedBy = .device
            guard (try? store.replaceGoalSettings(with: document)) != nil else { return false }
            Task { await writer.write(document, to: .goalSettings) }
        case .program(let old):
            var document = old
            document.version = store.program.version + 1
            document.updatedAt = stamp
            document.updatedBy = .device
            guard (try? store.replaceProgram(with: document)) != nil else { return false }
            Task { await writer.write(document, to: .program) }
        }
        return true
    }
}
