import Foundation

/// Where the Worker lives, and how its paths are built.
///
/// One place for every URL this package calls, so a path cannot drift from `edge/`.
public struct SyncEndpoint: Hashable, Sendable {
    public let origin: URL

    /// `origin` is the Worker's public origin, e.g. `https://ascension.example.workers.dev`.
    public init(origin: URL) {
        self.origin = origin
    }

    public init?(origin: String) {
        guard let url = URL(string: origin), url.scheme != nil, url.host != nil else { return nil }
        self.init(origin: url)
    }

    public var ingest: URL { origin.appending(path: "v1/ingest") }

    public var mutationsAck: URL { origin.appending(path: "v1/mutations/ack") }

    /// `GET /v1/mutations?since=<cursor>`. A nil cursor asks for the whole tail, which is
    /// what a fresh install needs.
    public func mutations(since cursor: String?) -> URL {
        let base = origin.appending(path: "v1/mutations")
        guard let cursor, !cursor.isEmpty else { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "since", value: cursor)]
        return components?.url ?? base
    }

    public func document(_ key: SyncDocumentKey) -> URL {
        origin.appending(path: "v1/documents/\(key.rawValue)")
    }
}

/// The three documents Muse may write (`docs/EXPORT_SCHEMA.md` §2). A closed set, so a
/// typo cannot become a `PUT` to a path the Worker does not serve.
public enum SyncDocumentKey: String, Codable, Hashable, Sendable, CaseIterable {
    case goalSettings
    case program
    case flags
}
