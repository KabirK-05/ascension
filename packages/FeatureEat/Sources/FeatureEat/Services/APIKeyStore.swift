import Foundation
import Security

/// The API keys this feature can hold: the USDA key search needs, and the Claude key
/// spec §F3 leaves optional and §8 says belongs in the Keychain. Neither is required —
/// staples, barcodes and manual entry work with neither set.
public enum APIKeyKind: String, Sendable, CaseIterable {
    case usda
    case anthropic
}

/// Where a key lives. Spec §8: in the Keychain, never in the repo.
public protocol APIKeyStore: Sendable {
    func apiKey(for kind: APIKeyKind) -> String?
    func setAPIKey(_ key: String?, for kind: APIKeyKind) throws
}

public enum APIKeyStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// The Keychain, as a generic password per key kind.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: a nightly background export may
/// need it while the phone is locked, and a key the user typed on this phone has no
/// business syncing anywhere else.
public struct KeychainAPIKeyStore: APIKeyStore {
    private let service: String

    public init(service: String = "com.kabirkumar.ascension.apikeys") {
        self.service = service
    }

    public func apiKey(for kind: APIKeyKind) -> String? {
        var query = baseQuery(for: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    public func setAPIKey(_ key: String?, for kind: APIKeyKind) throws {
        let query = baseQuery(for: kind)
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmed, !trimmed.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw APIKeyStoreError.keychain(status)
            }
            return
        }

        let data = Data(trimmed.utf8)
        let update = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw APIKeyStoreError.keychain(updated) }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw APIKeyStoreError.keychain(added) }
    }

    private func baseQuery(for kind: APIKeyKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
    }
}

/// An in-memory key store for previews and tests. Never reaches the Keychain.
public final class EphemeralAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [APIKeyKind: String]

    public init(keys: [APIKeyKind: String] = [:]) {
        self.keys = keys
    }

    public func apiKey(for kind: APIKeyKind) -> String? {
        lock.withLock { keys[kind] }
    }

    public func setAPIKey(_ key: String?, for kind: APIKeyKind) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock { keys[kind] = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }
}
