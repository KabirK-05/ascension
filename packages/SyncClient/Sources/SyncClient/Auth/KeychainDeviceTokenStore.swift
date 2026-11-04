import Foundation

#if canImport(Security)
import Security
#endif

/// The device token in the Keychain, and nowhere else.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: a background push or a
/// `BGProcessingTask` has to read it while the phone is locked, but it must never ride a
/// backup to another device. The token is never returned in an error and never logged.
public struct KeychainDeviceTokenStore: WritableDeviceTokenStore {
    public static let defaultService = "com.kabirkumar.ascension.device-token"

    private let service: String
    private let account: String

    public init(service: String = defaultService, account: String = "worker") {
        self.service = service
        self.account = account
    }

    #if canImport(Security)
    public func token() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw DeviceTokenStoreError.keychainFailure(status: status)
        }
        guard let data = item as? Data else { throw DeviceTokenStoreError.notUTF8 }
        guard let text = String(data: data, encoding: .utf8) else {
            throw DeviceTokenStoreError.notUTF8
        }
        return text
    }

    public func save(token: String) throws {
        guard let data = token.data(using: .utf8) else { throw DeviceTokenStoreError.notUTF8 }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw DeviceTokenStoreError.keychainFailure(status: status)
        }
        var insert = baseQuery()
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw DeviceTokenStoreError.keychainFailure(status: added)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeviceTokenStoreError.keychainFailure(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    #else
    public func token() throws -> String? { throw DeviceTokenStoreError.unavailable }
    public func save(token: String) throws { throw DeviceTokenStoreError.unavailable }
    public func clear() throws { throw DeviceTokenStoreError.unavailable }
    #endif
}
