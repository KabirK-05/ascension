import Foundation
import SyncClient

/// Who this phone is to the Worker, and whether it can talk to it at all.
///
/// Two separate things, and conflating them is the mistake this type exists to prevent:
///
/// - ``deviceId`` is **ours to mint**. `docs/TECH_STACK.md` §2.6 says it is a random UUID
///   generated on first launch, and nothing outside the device has to agree to it, so the
///   shell creates one and keeps it.
/// - ``canReachWorker`` reports whether a **device token** is present. That token is the
///   Worker's own `DEVICE_TOKEN` secret (`edge/src/env.ts`, set with `wrangler secret`),
///   so the phone cannot invent one: a generated value would be rejected by every request.
///   Until it is installed the remote bridge stays off rather than failing in a loop.
struct DeviceIdentity: Sendable {
    let deviceId: String

    /// False when the Keychain refused to keep the id, so a reader knows the id above is
    /// good for this launch only and will differ next time.
    let isPersisted: Bool

    /// True when a device token is in the Keychain, which is what makes sync possible.
    let canReachWorker: Bool
}

/// Reads the device identity, minting the id on first launch.
///
/// The Keychain is reached through `SyncClient`'s own `KeychainDeviceTokenStore`, pointed at
/// a second service: it already has the right accessibility class
/// (`AfterFirstUnlockThisDeviceOnly`, so a background wake can read it and a backup cannot
/// carry it to another phone) and it is already tested. A second hand-written Keychain
/// wrapper in the shell would be the same code with none of that.
enum DeviceIdentityProvisioner {
    static let identifierService = "com.kabirkumar.ascension.device-id"

    static func identifierStore() -> KeychainDeviceTokenStore {
        KeychainDeviceTokenStore(service: identifierService, account: "device")
    }

    /// The stored id, or a freshly minted and stored one.
    ///
    /// Never throws and never traps: a launch must not fail because the Keychain is
    /// unavailable. A failure to store is reported through ``DeviceIdentity/isPersisted``
    /// instead, because an id that changes every launch would make the Worker's rollups
    /// look like they came from a new device each time.
    static func provision(
        identifiers: any WritableDeviceTokenStore = identifierStore(),
        tokens: any DeviceTokenStore = KeychainDeviceTokenStore(),
        mint: () -> String = { UUID().uuidString }
    ) -> DeviceIdentity {
        let hasToken = (try? tokens.token()).flatMap { $0 }.map { !$0.isEmpty } ?? false

        if let existing = (try? identifiers.token()).flatMap({ $0 }), !existing.isEmpty {
            return DeviceIdentity(deviceId: existing, isPersisted: true,
                                  canReachWorker: hasToken)
        }

        let minted = mint()
        var stored = false
        do {
            try identifiers.save(token: minted)
            stored = true
        } catch {
            stored = false
        }
        return DeviceIdentity(deviceId: minted, isPersisted: stored, canReachWorker: hasToken)
    }
}
