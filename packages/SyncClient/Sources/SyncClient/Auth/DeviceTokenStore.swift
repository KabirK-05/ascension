import Foundation

/// Where the phone↔Worker device token comes from (`docs/TECH_STACK.md` §2.6).
///
/// A protocol so the Keychain stays out of the tests, and so no test ever needs a real
/// token. Implementations must never log, print or include the token in an error.
public protocol DeviceTokenStore: Sendable {
    /// The stored token, or `nil` when the device has not been paired yet.
    func token() throws -> String?
}

/// A store that can also be written, which pairing needs.
public protocol WritableDeviceTokenStore: DeviceTokenStore {
    func save(token: String) throws
    func clear() throws
}

/// A token held in memory for the life of the process. For tests, and for a preview build.
public struct InMemoryDeviceTokenStore: DeviceTokenStore {
    private let value: String?

    public init(token: String?) {
        self.value = token
    }

    public func token() throws -> String? { value }
}

/// What went wrong reaching the Keychain. Never carries the token.
public enum DeviceTokenStoreError: Error, Hashable, Sendable, CustomStringConvertible {
    case keychainFailure(status: Int32)
    case notUTF8
    case unavailable

    public var description: String {
        switch self {
        case .keychainFailure(let status): return "keychain failed with OSStatus \(status)"
        case .notUTF8: return "the stored token was not valid UTF-8"
        case .unavailable: return "no Keychain on this platform"
        }
    }
}
