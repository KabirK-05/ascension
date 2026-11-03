import Foundation

#if canImport(UIKit) && os(iOS)
import UIKit
#endif

/// APNs registration, and what to do with the token that comes back.
///
/// The token has to reach the Worker before it can push, but the endpoint that takes it is
/// the Worker's to define (ASC-13). So this type registers, formats, and hands the token to
/// a closure the app shell supplies — it does not invent a path to `POST` it to.
public struct RemoteNotificationRegistrar: Sendable {
    /// Called with the hex token on every registration, including the ones after a token
    /// rotation. APNs re-issues tokens, so this fires more than once per install.
    public typealias TokenHandler = @Sendable (String) async -> Void

    private let onToken: TokenHandler

    public init(onToken: @escaping TokenHandler) {
        self.onToken = onToken
    }

    /// Asks the system for a device token. No authorization prompt: a silent
    /// `content-available` push needs no user permission, which is why the only thing in
    /// `UIBackgroundModes` for this is `remote-notification`.
    @MainActor
    public func register() {
        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Forwarded from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public func received(deviceToken: Data) async {
        await onToken(Self.hex(deviceToken))
    }

    /// APNs tokens travel as lowercase hex.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
