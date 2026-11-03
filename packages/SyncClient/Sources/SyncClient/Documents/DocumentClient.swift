import AscensionCore
import Foundation

/// What a document write did, including how it got there.
public struct DocumentWriteResult: Hashable, Sendable {
    public var document: RemoteDocument
    /// How many `PUT`s it took. More than one means an `If-Match` race was merged.
    public var attempts: Int
    public var merges: [DocumentMerge.Outcome]

    public var didMerge: Bool { !merges.isEmpty }
}

/// Stream B's other half: the phone editing a document the cloud also owns.
///
/// `PUT /v1/documents/<key>` with `If-Match: <version>`. On `409` the Worker answers with
/// the document as it now stands; the loser merges last-write-wins per field by timestamp
/// and tries again. The retry budget is bounded — a device that keeps losing is a device
/// racing something that is writing continuously, and looping forever would drain the
/// battery to lose again.
public struct DocumentClient: Sendable {
    /// Three `PUT`s. One lost race is ordinary, two is unusual, three means something else
    /// is writing in a loop and this device should back off and report.
    public static let defaultMaxAttempts = 3

    private let session: SyncSession
    private let endpoint: SyncEndpoint
    private let clock: any SyncClock
    private let maxAttempts: Int

    public init(session: SyncSession, endpoint: SyncEndpoint, clock: any SyncClock,
                maxAttempts: Int = DocumentClient.defaultMaxAttempts) {
        self.session = session
        self.endpoint = endpoint
        self.clock = clock
        self.maxAttempts = max(1, maxAttempts)
    }

    public func fetch(_ key: SyncDocumentKey) async throws -> RemoteDocument {
        let request = HTTPRequest(method: .get, url: endpoint.document(key))
        let response = try await session.send(request)
        guard response.isSuccess else { throw response.failure() }
        return try Self.document(key: key, from: response.body)
    }

    /// Writes `body` to `key`, merging and retrying if the version moved underneath.
    ///
    /// `version` is the version the local edit was made against. `updatedAt` is when the
    /// local edit happened, which is what the merge compares; it defaults to now.
    @discardableResult
    public func write(_ body: [String: JSONValue], to key: SyncDocumentKey,
                      ifMatch version: Int,
                      localUpdatedAt: Timestamp? = nil) async throws -> DocumentWriteResult {
        var pending = body.filter { !RemoteDocument.envelopeKeys.contains($0.key) }
        var expected = version
        var stamp = localUpdatedAt ?? clock.timestamp
        var merges: [DocumentMerge.Outcome] = []

        for attempt in 1...maxAttempts {
            let response = try await put(pending, to: key, ifMatch: expected)
            if response.isSuccess {
                return DocumentWriteResult(document: try Self.document(key: key, from: response.body),
                                           attempts: attempt, merges: merges)
            }
            guard response.status == 409 else { throw response.failure() }
            let current = try Self.document(key: key, from: response.body)
            let outcome = DocumentMerge.lastWriteWins(local: pending, localUpdatedAt: stamp,
                                                      remote: current.body,
                                                      remoteUpdatedAt: current.updatedAt)
            merges.append(outcome)
            pending = outcome.body
            expected = current.version
            // The merged body is a new edit, made now, against the version just seen.
            stamp = clock.timestamp
        }
        throw SyncError.conflictUnresolved(key: key, attempts: maxAttempts)
    }

    /// Writes one of `AscensionCore`'s document types, taking the `If-Match` version from
    /// the document itself and stripping the envelope keys from its body.
    @discardableResult
    public func write(document: some Encodable & Sendable, to key: SyncDocumentKey,
                      ifMatch version: Int,
                      localUpdatedAt: Timestamp? = nil) async throws -> DocumentWriteResult {
        try await write(try RemoteDocument.body(of: document), to: key, ifMatch: version,
                        localUpdatedAt: localUpdatedAt)
    }

    private func put(_ body: [String: JSONValue], to key: SyncDocumentKey,
                     ifMatch version: Int) async throws -> HTTPResponse {
        let encoded = try SyncCoding.encode(JSONValue.object(body))
        let request = HTTPRequest(method: .put, url: endpoint.document(key),
                                  headers: ["Content-Type": "application/json",
                                            "If-Match": String(version)],
                                  body: encoded)
        return try await session.send(request)
    }

    /// A `409` body is the current document, which is the whole point of answering with
    /// one; a success body is the document as just written.
    private static func document(key: SyncDocumentKey, from data: Data) throws -> RemoteDocument {
        let value = try SyncCoding.decode(JSONValue.self, from: data)
        guard let object = value.objectValue else {
            throw SyncError.malformedResponse("\(key.rawValue) was not a JSON object")
        }
        let unwrapped = object["document"]?.objectValue ?? object
        return try RemoteDocument(key: key, json: unwrapped)
    }
}
