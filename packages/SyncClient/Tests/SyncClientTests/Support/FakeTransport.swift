import Foundation
import Testing

@testable import SyncClient

/// A scripted ``HTTPTransport``.
///
/// Records every request it was handed, so a test can assert what went on the wire —
/// including that a retry sent the *same* bytes — and answers from a queue of replies, so a
/// 409-then-200 or a 500-then-200 sequence is one line of setup.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case response(HTTPResponse)
        case failure(URLError)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [HTTPRequest] = []
    /// Used when the script runs out, so a test only scripts what it cares about.
    private let fallback: Reply

    init(replies: [Reply], fallback: Reply = .response(HTTPResponse(status: 200, body: Data()))) {
        self.replies = replies
        self.fallback = fallback
    }

    convenience init(json: String, status: Int = 200) {
        self.init(replies: [.response(.json(status: status, json))])
    }

    var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    var requestCount: Int { requests.count }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply: Reply = lock.withLock {
            recorded.append(request)
            return replies.isEmpty ? fallback : replies.removeFirst()
        }
        switch reply {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }
}

extension HTTPResponse {
    static func json(status: Int = 200, _ body: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"],
                     body: Data(body.utf8))
    }
}

extension HTTPRequest {
    var bearerToken: String? {
        guard let value = header("Authorization"), value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst("Bearer ".count))
    }
}
