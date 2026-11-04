import Foundation

/// One entry in the append-only write log (`docs/EXPORT_SCHEMA.md` §3).
///
/// `id` is a ULID, so ordering is lexicographic. `appliedAt` is set by the device after
/// it applies a Tier-2 mutation; Tier-1 mutations are applied by the Worker and marked
/// immediately. Both stay explicitly `null` until then.
public struct Mutation: Codable, Hashable, Sendable {
    public var id: String
    public var createdAt: Timestamp
    public var actor: ActorKind
    public var kind: MutationKind
    public var payload: JSONValue
    public var appliedAt: Timestamp?
    public var appliedResult: JSONValue?

    public init(id: String, createdAt: Timestamp, actor: ActorKind, kind: MutationKind,
                payload: JSONValue, appliedAt: Timestamp? = nil,
                appliedResult: JSONValue? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.actor = actor
        self.kind = kind
        self.payload = payload
        self.appliedAt = appliedAt
        self.appliedResult = appliedResult
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(actor, forKey: .actor)
        try container.encode(kind, forKey: .kind)
        try container.encode(payload, forKey: .payload)
        try container.encodeNullable(appliedAt, forKey: .appliedAt)
        try container.encodeNullable(appliedResult, forKey: .appliedResult)
    }

    public var isApplied: Bool { appliedAt != nil }
}
