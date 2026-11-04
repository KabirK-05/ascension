import AscensionCore
import Foundation

/// One remote write that reached this device, in the words a person would use for it.
///
/// `docs/MUSE_CAPABILITIES.md` gives Muse full write authority over targets, the program
/// and the staples. That is only reasonable if the writes are visible and the important
/// ones are reversible, which is what this row is: what changed, when — and, for the two
/// documents worth reverting, the exact value it had before.
///
/// **No actor field, deliberately.** The Worker's `mutations` table records one, but
/// `SyncClient.LocalStateApplier` hands the device a payload and a mutation id and not the
/// actor, and that protocol belongs to another ticket's package. Every row here is a write
/// that arrived through the drain, so the list is remote writes by construction; printing
/// a guessed actor beside each one would be worse than printing none.
struct RecordedChange: Codable, Hashable, Sendable, Identifiable {
    /// The mutation's ULID, so a redelivered mutation cannot produce a second row.
    var id: String
    var at: Timestamp
    var kind: MutationKind

    /// Plain language, built by ``ChangeSummary`` at the moment the write was applied —
    /// the only moment both the old and the new value are in hand.
    var summary: String

    /// The document as it was before. `nil` for every kind there is nothing to put back:
    /// a logged meal is a fact about the day, not a setting.
    var previous: PreviousDocument?
    var undoneAt: Timestamp?

    var canUndo: Bool { previous != nil && undoneAt == nil }
}

/// The value a change replaced, kept whole rather than as a patch.
///
/// Whole, because a patch cannot be inverted safely: two `set_targets` in a row, undone
/// out of order, would reconstruct a document that never existed. Restoring the document
/// that *was* there is unambiguous.
enum PreviousDocument: Codable, Hashable, Sendable {
    case goalSettings(GoalSettingsDocument)
    case program(ProgramDocument)

    var key: SyncDocumentKeyName {
        switch self {
        case .goalSettings: return .goalSettings
        case .program: return .program
        }
    }
}

/// The document keys this ledger can restore. Mirrors `SyncClient.SyncDocumentKey`
/// without importing it, so the stored JSON does not depend on another package's enum.
enum SyncDocumentKeyName: String, Codable, Hashable, Sendable {
    case goalSettings
    case program
}
