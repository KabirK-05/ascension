import AscensionCore
import Foundation

/// The two remote food sources (spec §F3, §10), each behind a protocol so the screen's
/// logic is tested without a network and the app keeps working without one.
public protocol FoodSearching: Sendable {
    /// Whole foods by name. Throws `FoodLookupError.missingAPIKey` when no USDA key
    /// has been set — search is the only path that needs one.
    func search(_ query: String) async throws -> [FoodItemDTO]
}

public protocol BarcodeLookup: Sendable {
    /// The packaged food behind a barcode, or `nil` when the database has never seen it.
    func food(barcode: String) async throws -> FoodItemDTO?
}

public enum FoodLookupError: Error, Equatable {
    /// No USDA key in the Keychain. Search is unavailable; staples and manual entry
    /// are not affected.
    case missingAPIKey
    case offline
    /// The source answered, but with something this app will not put in front of the
    /// user or into Apple Health.
    case unusableResponse
    case http(Int)
}

/// The one HTTP call this feature makes, behind a protocol so every provider test runs
/// offline and a fixture can answer for the network.
public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPFetching: HTTPFetching {
    private let session: URLSession

    /// Short timeouts and no cellular-waiting: a food lookup that has not answered in
    /// ten seconds has failed, and the staples path is one tap away.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FoodLookupError.unusableResponse
            }
            return (data, http)
        } catch let error as URLError {
            throw Self.translate(error)
        }
    }

    private static func translate(_ error: URLError) -> any Error {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .timedOut, .dataNotAllowed, .internationalRoamingOff:
            return FoodLookupError.offline
        default:
            return error
        }
    }
}
