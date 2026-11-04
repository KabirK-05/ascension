import Foundation
import SyncClient

/// Where the Cloudflare Worker lives, and whether the bridge may run at all.
///
/// The origin is **not** in the repository and is not a secret either: it is one
/// deployment's address, and hard-coding it would make a redeploy a code change. It is read
/// from `UserDefaults` under ``originKey``, which Settings (ASC-16) writes. Absent, the
/// bridge is simply unconfigured — the tabs all still work, nothing is pushed, and nothing
/// retries against a URL that does not exist.
///
/// Pair this with ``DeviceIdentity/canReachWorker``: an origin with no token and a token
/// with no origin are both unconfigured, and ``RemoteBridgeConfiguration/isReady`` is the
/// single question the composition root asks.
struct RemoteBridgeConfiguration: Sendable {
    static let originKey = "ascension.worker.origin"

    let endpoint: SyncEndpoint?
    let hasDeviceToken: Bool

    /// Both halves present. Only then is there anything to start.
    var isReady: Bool { endpoint != nil && hasDeviceToken }

    init(endpoint: SyncEndpoint?, hasDeviceToken: Bool) {
        self.endpoint = endpoint
        self.hasDeviceToken = hasDeviceToken
    }

    init(defaults: UserDefaults = .standard, identity: DeviceIdentity) {
        self.init(endpoint: Self.endpoint(in: defaults),
                  hasDeviceToken: identity.canReachWorker)
    }

    /// A malformed stored origin resolves to `nil` rather than to a URL that would 404 on
    /// every request: `SyncEndpoint`'s failable initialiser already insists on a scheme and
    /// a host.
    static func endpoint(in defaults: UserDefaults) -> SyncEndpoint? {
        guard let raw = defaults.string(forKey: originKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return SyncEndpoint(origin: raw)
    }

    /// What a reader should be told about the bridge. Facts, in one short phrase.
    var summary: String {
        switch (endpoint != nil, hasDeviceToken) {
        case (true, true): return "paired"
        case (true, false): return "no device token"
        case (false, true): return "no worker origin"
        case (false, false): return "not configured"
        }
    }
}
