import AscensionCore
import Foundation

/// Resolving a lost `If-Match` race: last write wins, per field, by timestamp
/// (`docs/TECH_STACK.md` §2.3).
///
/// The document carries one `updatedAt`, not one per field, so "per field by timestamp"
/// can only mean this: walk the two bodies field by field, and where they disagree take
/// the side whose document was stamped later. Fields only one side has are kept — a new
/// field is not a disagreement — and fields that agree are left alone, so an unrelated
/// edit by Muse survives a local one and vice versa.
///
/// Pure, and deterministic down to the ordering of nested keys.
public enum DocumentMerge {
    /// The merge result and which side won the fields that differed.
    public struct Outcome: Hashable, Sendable {
        public var body: [String: JSONValue]
        /// Fields where the two sides disagreed and the remote copy was the newer one.
        public var takenFromRemote: [String]
        /// Fields where the two sides disagreed and the local copy was the newer one.
        public var takenFromLocal: [String]

        public var hadConflicts: Bool { !takenFromRemote.isEmpty || !takenFromLocal.isEmpty }
    }

    /// Merges the local edit against the document the Worker returned with its `409`.
    public static func lastWriteWins(local: [String: JSONValue],
                                     localUpdatedAt: Timestamp,
                                     remote: [String: JSONValue],
                                     remoteUpdatedAt: Timestamp) -> Outcome {
        let remoteIsNewer = isNewer(remoteUpdatedAt, than: localUpdatedAt)
        var body: [String: JSONValue] = [:]
        var fromRemote: [String] = []
        var fromLocal: [String] = []

        for key in Set(local.keys).union(remote.keys).sorted() {
            switch (local[key], remote[key]) {
            case (let mine?, let theirs?) where mine == theirs:
                body[key] = mine
            case (let mine?, let theirs?):
                body[key] = remoteIsNewer ? theirs : mine
                if remoteIsNewer { fromRemote.append(key) } else { fromLocal.append(key) }
            case (let mine?, nil):
                body[key] = mine
            case (nil, let theirs?):
                body[key] = theirs
            case (nil, nil):
                continue
            }
        }
        return Outcome(body: body, takenFromRemote: fromRemote, takenFromLocal: fromLocal)
    }

    /// Ties go to the remote copy: it is the one already stored, so keeping it is the
    /// smaller change and two devices resolving the same tie land in the same place.
    private static func isNewer(_ lhs: Timestamp, than rhs: Timestamp) -> Bool {
        guard let left = lhs.date, let right = rhs.date else {
            return lhs.rawValue >= rhs.rawValue
        }
        return left >= right
    }
}
