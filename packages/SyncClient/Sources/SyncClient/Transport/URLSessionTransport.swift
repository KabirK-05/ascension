import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ``HTTPTransport`` over `URLSession`.
///
/// The only type in this package that touches the network. Nothing else imports
/// `URLSession`, which is what keeps the rest testable on macOS without a server.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.session = session
        self.timeout = timeout
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.transport(URLError(.badServerResponse))
        }
        return HTTPResponse(status: http.statusCode, headers: Self.headers(of: http), body: data)
    }

    private static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let text = value as? String else { continue }
            headers[name] = text
        }
        return headers
    }
}
