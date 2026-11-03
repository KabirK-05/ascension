import AscensionCore
import ExportKit
import Foundation

/// Runs an export over the ledger and the store.
///
/// `ExportKit` touches no store, no network and no framework of its own: it takes one
/// `ExportSnapshot` of value types. Assembling that snapshot is the shell's job, and this
/// is it.
///
/// The destination is a security-scoped bookmark the user grants once. Until they have,
/// ``hasDestination`` is false and a run returns `nil` rather than throwing on every
/// nightly wake — there is nowhere to write, which is a configuration state and not a
/// failure. The folder picker belongs to Settings (ASC-16).
struct ExportRunner: Sendable {
    private let store: LocalStore
    private let ledger: RollupStore
    private let destination: ExportDestination

    init(store: LocalStore, ledger: RollupStore, destination: ExportDestination) {
        self.store = store
        self.ledger = ledger
        self.destination = destination
    }

    var hasDestination: Bool { destination.hasDestination }

    /// Writes the export, or returns `nil` when there is no folder to write to.
    ///
    /// `suggestions` is empty on purpose: spec §7 defines no suggestion entity, so the app
    /// has nowhere to keep an open one. The Worker holds them, and the field exists in the
    /// export for when a ticket gives the app a store for them.
    @discardableResult
    func run(trigger: ExportTrigger) async -> ExportResult? {
        guard destination.hasDestination else { return nil }

        let rollups = await ledger.load().all
        let dates = rollups.map(\.date)
        let documents = await store.documents
        let snapshot = await ExportSnapshot(
            rollups: rollups,
            documents: documents,
            meals: store.mealEntries(in: dates),
            suggestions: [],
            exerciseNames: store.exerciseNames)

        let service = ExportService(
            destination: destination,
            environment: ExportEnvironment(goalSettings: documents.goalSettings))

        guard let result = try? service.run(snapshot, trigger: trigger) else { return nil }
        await record(result)
        return result
    }

    /// `ExportKit` owns no store deliberately, so the manifest is persisted here.
    private func record(_ result: ExportResult) async {
        await MainActor.run {
            store.context.insert(ExportManifest(exportedAt: result.exportedAt,
                                                recordCounts: result.recordCounts))
            try? store.context.save()
        }
    }
}
