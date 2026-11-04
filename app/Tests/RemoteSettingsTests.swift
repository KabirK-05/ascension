import Foundation
import SyncClient
import Testing

@testable import Ascension

/// Pairing is what ASC-20 left unreachable: `SyncEngine` is built only when both halves
/// exist, and before this ticket there was no way to put either of them on the device.
@Suite("remote settings")
struct RemoteSettingsTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ascension.tests.remote.\(UUID().uuidString)") ?? .standard
    }

    @Test("a stored origin is read back, and resolves to an endpoint")
    func origin() {
        let settings = RemoteSettings(defaults: defaults(), tokens: RecordingTokenStore())
        #expect(settings.save(origin: "  https://ascension.example.workers.dev  "))
        #expect(settings.origin == "https://ascension.example.workers.dev")
    }

    @Test("a malformed origin is kept but reported as unresolvable")
    func malformedOrigin() {
        let settings = RemoteSettings(defaults: defaults(), tokens: RecordingTokenStore())
        #expect(settings.save(origin: "not a url") == false)
        #expect(settings.origin == "not a url")
    }

    @Test("emptying the field clears the origin")
    func clearedOrigin() {
        let settings = RemoteSettings(defaults: defaults(), tokens: RecordingTokenStore())
        settings.save(origin: "https://ascension.example.workers.dev")
        #expect(settings.save(origin: "   ") == false)
        #expect(settings.origin.isEmpty)
    }

    @Test("a token too short to be the Worker's secret is refused, not stored")
    func shortTokenRefused() {
        let tokens = RecordingTokenStore()
        let settings = RemoteSettings(defaults: defaults(), tokens: tokens)
        #expect(settings.save(token: "abc") == false)
        #expect(settings.hasToken == false)
    }

    @Test("a stored token is never shown, only its last four characters")
    func tokenIsMasked() {
        let tokens = RecordingTokenStore()
        let settings = RemoteSettings(defaults: defaults(), tokens: tokens)
        let secret = "s3cr3t-worker-device-token-9f4a"
        #expect(settings.save(token: secret))
        let masked = settings.maskedToken
        #expect(masked == "•••• 9f4a")
        #expect(masked?.contains("s3cr3t") == false)
    }

    @Test("the mask does not leak the secret's length")
    func maskIsFixedWidth() {
        let settings = RemoteSettings(defaults: defaults(), tokens: RecordingTokenStore())
        settings.save(token: String(repeating: "a", count: 64) + "beef")
        #expect(settings.maskedToken == "•••• beef")
    }

    @Test("forgetting the token leaves nothing behind")
    func clearToken() {
        let settings = RemoteSettings(defaults: defaults(), tokens: RecordingTokenStore())
        settings.save(token: "s3cr3t-worker-device-token-9f4a")
        #expect(settings.clearToken())
        #expect(settings.hasToken == false)
        #expect(settings.maskedToken == nil)
    }

    @Test("a Keychain that refuses keeps nothing and says so")
    func failingKeychain() {
        let settings = RemoteSettings(defaults: defaults(), tokens: FailingTokenStore())
        #expect(settings.save(token: "s3cr3t-worker-device-token-9f4a") == false)
        #expect(settings.hasToken == false)
    }

    @Test("the last push is remembered across reads, and absent until there is one")
    func activity() {
        let suite = defaults()
        let activity = SyncActivity(defaults: suite)
        #expect(activity.lastPushAt == nil)
        let instant = Date(timeIntervalSince1970: 1_793_000_000)
        activity.recordPush(at: instant)
        #expect(SyncActivity(defaults: suite).lastPushAt == instant)
    }
}
