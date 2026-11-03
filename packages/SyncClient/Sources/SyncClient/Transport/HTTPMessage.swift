import Foundation

/// An HTTP request as a value.
///
/// `URLSession` is deliberately absent from this type so the whole client can be driven
/// from a test on macOS, and so a request can be compared byte for byte.
public struct HTTPRequest: Hashable, Sendable {
    public enum Method: String, Hashable, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    public var method: Method
    public var url: URL
    /// Header names are compared case-insensitively by ``header(_:)``; the dictionary keeps
    /// whatever casing the caller used, so a recorded request reads like the wire.
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The request with `value` set for `name`, replacing any existing casing of it.
    public func settingHeader(_ name: String, _ value: String) -> HTTPRequest {
        var copy = self
        copy.headers = copy.headers.filter { $0.key.caseInsensitiveCompare(name) != .orderedSame }
        copy.headers[name] = value
        return copy
    }
}

/// An HTTP response as a value.
public struct HTTPResponse: Hashable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// A 5xx, a 408 or a 429 — worth another attempt. A 4xx otherwise is the client's own
    /// fault and retrying it would only repeat the mistake.
    public var isRetryable: Bool {
        status >= 500 || status == 408 || status == 429
    }
}

/// The one seam `URLSession` sits behind.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
