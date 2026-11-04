import AscensionCore
import ExportKit
import Foundation
import HealthBridge
import SyncClient
import Testing

@testable import Ascension

/// The shell's configuration is all "is this device set up for X", and every answer has to
/// be *no* without breaking anything — the app ships before a Worker exists, before a
/// folder is picked and before a Watch is paired.
@Suite("shell configuration")
struct ConfigurationTests {
    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "ascension.tests.\(name).\(UUID().uuidString)")
        return suite ?? .standard
    }

    @Test("with nothing configured the remote bridge is simply not ready")
    func unconfiguredBridge() {
        let configuration = RemoteBridgeConfiguration(endpoint: nil, hasDeviceToken: false)

        #expect(!configuration.isReady)
        #expect(configuration.summary == "not configured")
    }

    @Test("an origin with no token is not ready, and says which half is missing")
    func halfConfiguredBridge() throws {
        let endpoint = try #require(SyncEndpoint(origin: "https://edge.example.test"))
        let configuration = RemoteBridgeConfiguration(endpoint: endpoint, hasDeviceToken: false)

        #expect(!configuration.isReady)
        #expect(configuration.summary == "no device token")
    }

    @Test("a stored origin is read, and a malformed one is not")
    func originParsing() {
        let store = defaults("origin")
        #expect(RemoteBridgeConfiguration.endpoint(in: store) == nil)

        store.set("not a url", forKey: RemoteBridgeConfiguration.originKey)
        #expect(RemoteBridgeConfiguration.endpoint(in: store) == nil)

        store.set("  https://edge.example.test  ", forKey: RemoteBridgeConfiguration.originKey)
        #expect(RemoteBridgeConfiguration.endpoint(in: store)?.origin.host() == "edge.example.test")
    }

    /// `nil` zones are the honest answer while nothing stores a maximum, and the fallbacks
    /// for it are documented behaviour in `HealthBridge` rather than silent wrongness.
    @Test("heart-rate zones exist only once a plausible maximum is stored")
    func heartRateZones() {
        #expect(HeartRateConfiguration(maximumBpm: nil).zones == nil)
        #expect(HeartRateConfiguration(maximumBpm: 300).zones != nil)

        let store = defaults("heartRate")
        #expect(HeartRateConfiguration(defaults: store).zones == nil)

        store.set(40.0, forKey: HeartRateConfiguration.maximumKey)
        #expect(HeartRateConfiguration(defaults: store).maximumBpm == nil)

        store.set(191.0, forKey: HeartRateConfiguration.maximumKey)
        #expect(HeartRateConfiguration(defaults: store).maximumBpm == 191)
    }

    @Test("flags start as the seed, and only a known key changes one")
    func flagsStore() {
        let flags = FlagsStore(defaults: defaults("flags"))
        let seeded = flags.document

        flags.apply(key: "museWritesEnabled", value: .bool(!seeded.museWritesEnabled))
        #expect(flags.document.museWritesEnabled == !seeded.museWritesEnabled)
        #expect(flags.document.version == seeded.version + 1)

        flags.apply(key: "notAFlag", value: .bool(true))
        flags.apply(key: "museWritesEnabled", value: .string("yes"))
        #expect(flags.document.version == seeded.version + 1)
    }

    /// `BGTaskScheduler` allows one handler per identifier, and `ExportKit` and `SyncClient`
    /// chose the same one deliberately — the nightly export and the nightly push are one
    /// job. If these ever diverge the shell would register two handlers for a single
    /// permitted identifier, which is a crash on the first background wake.
    @Test("the write mode is a flag like any other, and only a known mode is taken")
    func writeMode() {
        let flags = FlagsStore(defaults: defaults("writeMode"))
        #expect(flags.document.museWriteMode == Seed.flags.museWriteMode)

        flags.apply(key: "museWriteMode", value: .string("apply"))
        #expect(flags.document.museWriteMode == .apply)

        flags.apply(key: "museWriteMode", value: .string("whatever"))
        #expect(flags.document.museWriteMode == .apply)

        flags.apply(key: "museWriteMode", value: .bool(true))
        #expect(flags.document.museWriteMode == .apply)
    }

    @Test("setting the write mode bumps the document so the Worker sees a new version")
    func writeModeBumpsVersion() {
        let flags = FlagsStore(defaults: defaults("writeModeVersion"))
        let before = flags.document.version
        let updated = flags.setMuseWriteMode(.apply)
        #expect(updated.museWriteMode == .apply)
        #expect(updated.version == before + 1)
        // Setting the mode it is already in changes nothing, version included.
        #expect(flags.setMuseWriteMode(.apply).version == before + 1)
    }

    @Test("the nightly export and the nightly push share one background identifier")
    func nightlyIdentifiersAgree() {
        #expect(NightlyExport.taskIdentifier == SyncTaskIdentifier.nightlyPush)
        #expect(SyncTaskIdentifier.nightlyPush != SyncTaskIdentifier.mutationDrain)
        #expect(NightlyExport.taskIdentifier == "com.kabirkumar.ascension.nightly-export")
        #expect(SyncTaskIdentifier.mutationDrain == "com.kabirkumar.ascension.rollup-sync")
    }
}
