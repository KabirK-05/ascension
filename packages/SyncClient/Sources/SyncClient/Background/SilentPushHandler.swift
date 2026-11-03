import Foundation

/// The silent-push wake path (`docs/TECH_STACK.md` §2.4).
///
/// The Worker sends a `content-available` push whenever it queues a mutation, so a meal
/// Muse logged reaches Apple Health in seconds instead of at the next refresh.
///
/// **Correctness never depends on the push arriving.** A push is throttled, dropped while
/// the device is offline, and discarded entirely when the user has disabled background
/// refresh. Everything it does, the foreground sync and the `BGAppRefreshTask` also do —
/// this only makes it sooner. Nothing is written here that the other two paths do not
/// write, and the result of ``handle(userInfo:)`` reports whether anything happened rather
/// than whether a push was seen.
public struct SilentPushHandler: Sendable {
    /// The key the Worker's payload carries. Checked so an unrelated push — a future
    /// user-visible notification — does not trigger a drain.
    public static let payloadKey = "ascension"
    public static let drainReason = "mutations"

    private let engine: SyncEngine

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    /// Whether `userInfo` is the Worker asking for a drain.
    ///
    /// `{"aps":{"content-available":1},"ascension":{"reason":"mutations"}}`. A push with the
    /// `aps` flag but no recognised reason is ignored, not guessed at.
    public static func wantsDrain(userInfo: [AnyHashable: Any]) -> Bool {
        guard let payload = userInfo[payloadKey] as? [String: Any] else { return false }
        return payload["reason"] as? String == drainReason
    }

    /// Drains if the push asked for it. Returns `nil` when the push was not ours, so the
    /// caller can answer `.noData` without having touched the network.
    @discardableResult
    public func handle(userInfo: [AnyHashable: Any]) async throws -> DrainReport? {
        guard Self.wantsDrain(userInfo: userInfo) else { return nil }
        return try await engine.drain()
    }
}
