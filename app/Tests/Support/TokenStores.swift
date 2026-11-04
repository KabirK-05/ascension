import Foundation
import SyncClient

/// A writable token store in memory, so the device-id path is testable without a Keychain.
final class RecordingTokenStore: WritableDeviceTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(token: String? = nil) {
        self.value = token
    }

    func token() throws -> String? { lock.withLock { value } }

    func save(token: String) throws { lock.withLock { value = token } }

    func clear() throws { lock.withLock { value = nil } }
}

/// A Keychain that is there but will not keep anything — a real state on a device whose
/// keychain is locked, and the one the shell has to report rather than paper over.
struct FailingTokenStore: WritableDeviceTokenStore {
    func token() throws -> String? { nil }

    func save(token: String) throws {
        throw DeviceTokenStoreError.keychainFailure(status: -25_308)
    }

    func clear() throws {
        throw DeviceTokenStoreError.keychainFailure(status: -25_308)
    }
}
