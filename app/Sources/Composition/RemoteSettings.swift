import Foundation
import SyncClient

/// The writable half of ``RemoteBridgeConfiguration``: what Settings changes when the
/// device is paired with the Worker.
///
/// The two halves live in two different places on purpose. The **origin** is one
/// deployment's address — not a secret, and in `UserDefaults` so a redeploy is not a code
/// change. The **token** is the Worker's own `DEVICE_TOKEN` secret (`edge/src/env.ts`),
/// which the phone cannot mint and which there is no pairing endpoint to fetch, so it is
/// typed in once and kept in the Keychain with the accessibility class a background wake
/// needs.
///
/// Nothing here ever returns the token. ``maskedToken`` is the only thing a screen may
/// show, and it is four characters and some dots.
struct RemoteSettings: Sendable {
    /// The shortest thing worth storing. A token shorter than this is a typo, and storing
    /// it would turn every request into a 401 the user has no way to explain.
    static let minimumTokenLength = 16

    // Thread-safe and documented as such, but not marked `Sendable` — the exception is
    // scoped to this one property, exactly as `FlagsStore` scopes its own.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let tokens: any WritableDeviceTokenStore

    init(defaults: UserDefaults = .standard,
         tokens: any WritableDeviceTokenStore = KeychainDeviceTokenStore()) {
        self.defaults = defaults
        self.tokens = tokens
    }

    // MARK: - Origin

    var origin: String {
        defaults.string(forKey: RemoteBridgeConfiguration.originKey) ?? ""
    }

    /// Stores a trimmed origin, or clears it when the field is emptied.
    ///
    /// Returns whether what was stored resolves to an endpoint. A value that does not is
    /// still stored — refusing the keystroke would be worse than showing the status line
    /// say the bridge is not configured — but the caller can tell.
    @discardableResult
    func save(origin raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: RemoteBridgeConfiguration.originKey)
            return false
        }
        defaults.set(trimmed, forKey: RemoteBridgeConfiguration.originKey)
        return SyncEndpoint(origin: trimmed) != nil
    }

    // MARK: - Token

    var hasToken: Bool {
        (try? tokens.token()).flatMap { $0 }.map { !$0.isEmpty } ?? false
    }

    /// The last four characters behind a fixed run of dots.
    ///
    /// Fixed, not proportional: a mask whose length tracks the secret's leaks the secret's
    /// length. `nil` when nothing is stored, which is what lets the row read as unset
    /// without a sentence saying so.
    var maskedToken: String? {
        guard let token = (try? tokens.token()).flatMap({ $0 }), !token.isEmpty else {
            return nil
        }
        return "•••• " + String(token.suffix(4))
    }

    /// Stores a token, refusing one too short to be the Worker's secret.
    @discardableResult
    func save(token raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumTokenLength else { return false }
        do {
            try tokens.save(token: trimmed)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func clearToken() -> Bool {
        do {
            try tokens.clear()
            return true
        } catch {
            return false
        }
    }
}
