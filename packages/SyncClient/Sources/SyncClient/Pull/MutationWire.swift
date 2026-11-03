import AscensionCore
import Foundation

/// The body of `GET /v1/mutations?since=<cursor>`.
///
/// `cursor` is what to send as `since` next time. It is optional because the id of the
/// last mutation in the page is the same thing — ids are ULIDs, so lexicographic order is
/// chronological — and a Worker that omits it is still answerable. A bare array decodes
/// too, mirroring the latitude `POST /v1/ingest` already allows.
public struct MutationPage: Codable, Hashable, Sendable {
    public var schemaVersion: Int?
    public var mutations: [Mutation]
    public var cursor: String?

    public init(mutations: [Mutation], cursor: String? = nil, schemaVersion: Int? = nil) {
        self.schemaVersion = schemaVersion
        self.mutations = mutations
        self.cursor = cursor
    }

    public init(from decoder: any Decoder) throws {
        if let bare = try? decoder.singleValueContainer().decode([Mutation].self) {
            self.init(mutations: bare)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mutations: try container.decode([Mutation].self, forKey: .mutations),
                  cursor: try container.decodeIfPresent(String.self, forKey: .cursor),
                  schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion))
    }

    /// The page in the order it must be applied: by `id`, ascending.
    public var ordered: [Mutation] {
        mutations.sorted { $0.id < $1.id }
    }
}

/// The body of `POST /v1/mutations/ack`: the ids that actually applied, and nothing else.
public struct MutationAck: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var ids: [String]
    /// When the device applied them. The Worker stamps `appliedAt` from this, so a drain
    /// that happened offline keeps the instant it really happened.
    public var appliedAt: Timestamp

    public init(ids: [String], appliedAt: Timestamp,
                schemaVersion: Int = SyncClientModule.schemaVersion) {
        self.schemaVersion = schemaVersion
        self.ids = ids
        self.appliedAt = appliedAt
    }
}

/// What one drain did.
public struct DrainReport: Hashable, Sendable {
    /// Applied this run, in the order they were applied.
    public var applied: [String]
    /// Already in the ledger from an earlier delivery, so applied zero extra times.
    public var alreadyApplied: [String]
    /// The mutation that stopped the drain, if one did. Everything after it is untouched
    /// and stays queued: skipping it would apply Muse's writes out of order.
    public var blockedBy: BlockedMutation?
    /// The cursor now persisted. `nil` when nothing moved it.
    public var cursor: String?

    public init(applied: [String] = [], alreadyApplied: [String] = [],
                blockedBy: BlockedMutation? = nil, cursor: String? = nil) {
        self.applied = applied
        self.alreadyApplied = alreadyApplied
        self.blockedBy = blockedBy
        self.cursor = cursor
    }

    public var didApplyAnything: Bool { !applied.isEmpty }
}

/// A mutation that could not be applied, and how many times it has now failed.
public struct BlockedMutation: Hashable, Sendable {
    public var id: String
    public var kind: MutationKind
    public var reason: String
    public var failureCount: Int

    public init(id: String, kind: MutationKind, reason: String, failureCount: Int) {
        self.id = id
        self.kind = kind
        self.reason = reason
        self.failureCount = failureCount
    }
}
