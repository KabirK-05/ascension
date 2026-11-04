import AscensionCore
import Foundation

/// A document as the Worker serves it (`docs/EXPORT_SCHEMA.md` §2).
///
/// The split matters on the way back: `version`, `updatedAt` and `updatedBy` are columns on
/// the `documents` table, not part of the body, and `edge/src/db/documents.ts` composes
/// them back in on read. A `PUT` that echoed them inside the body would fail the Worker's
/// `strictObject` as a contract violation, so ``body`` holds the body alone.
public struct RemoteDocument: Hashable, Sendable {
    /// The keys that belong to the envelope rather than the body.
    ///
    /// `version`, `updatedAt` and `updatedBy` are the `documents` table's own columns.
    /// `schemaVersion` is added to every response by `edge/src/http/respond.ts`, and `key`
    /// identifies the row — so all of those arrive alongside a document and none of them
    /// may be echoed back inside one. `error`, `hint` and `issues` are there because a
    /// `409` answers with both a problem slug and the current document, and the Worker may
    /// return them flat rather than nested; stripping them keeps a merged body clean
    /// either way. No document body in §2 declares any of these names.
    public static let envelopeKeys: Set<String> = [
        "version", "updatedAt", "updatedBy", "schemaVersion", "key",
        "error", "hint", "issues"
    ]

    public var key: SyncDocumentKey
    public var version: Int
    public var updatedAt: Timestamp
    public var updatedBy: ActorKind
    public var body: [String: JSONValue]

    public init(key: SyncDocumentKey, version: Int, updatedAt: Timestamp,
                updatedBy: ActorKind, body: [String: JSONValue]) {
        self.key = key
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.body = body
    }

    /// Reads the flat object the Worker returns, splitting envelope from body.
    public init(key: SyncDocumentKey, json: [String: JSONValue]) throws {
        guard case .number(let version)? = json["version"] else {
            throw SyncError.malformedResponse("\(key.rawValue) carried no numeric version")
        }
        guard case .string(let stamp)? = json["updatedAt"], let updatedAt = Timestamp(rawValue: stamp)
        else {
            throw SyncError.malformedResponse("\(key.rawValue) carried no ISO-8601 updatedAt")
        }
        guard case .string(let actor)? = json["updatedBy"], let updatedBy = ActorKind(rawValue: actor)
        else {
            throw SyncError.malformedResponse("\(key.rawValue) carried an unknown updatedBy")
        }
        self.init(key: key, version: Int(version), updatedAt: updatedAt, updatedBy: updatedBy,
                  body: json.filter { !Self.envelopeKeys.contains($0.key) })
    }

    /// Decodes the body as the document type that owns it.
    public func decodeBody<T: Decodable>(as type: T.Type) throws -> T {
        try SyncCoding.decode(type, from: try SyncCoding.encode(JSONValue.object(body)))
    }
}

extension RemoteDocument {
    /// The body of a local document, with the envelope keys stripped.
    ///
    /// `AscensionCore`'s document types carry `version`/`updatedAt`/`updatedBy` inline —
    /// that is the shape the file export writes — so they are removed on the way to a
    /// `PUT`.
    public static func body(of document: some Encodable & Sendable) throws -> [String: JSONValue] {
        let value = try SyncCoding.decode(JSONValue.self, from: try SyncCoding.encode(document))
        guard let object = value.objectValue else {
            throw SyncError.malformedResponse("a document body must be a JSON object")
        }
        return object.filter { !envelopeKeys.contains($0.key) }
    }
}
