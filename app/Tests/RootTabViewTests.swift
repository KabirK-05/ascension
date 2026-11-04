import Foundation
import Testing

@testable import Ascension

/// The launch path, run for real.
///
/// Everything else in this target drives one piece with its dependencies faked. This builds
/// the actual composition root in the actual app sandbox — the store, the Keychain, the
/// HealthKit adapter, the Watch scheduler — because "it assembles" is the single claim this
/// ticket most needs to be true, and the pieces it is made of are exactly the ones that are
/// absent on a simulator.
@Suite("the app shell")
@MainActor
struct RootTabViewTests {
    @Test("the composition root builds, and the four tabs come out of it")
    func theShellAssembles() {
        let composition = AppComposition(defaults: UserDefaults(
            suiteName: "ascension.tests.shell.\(UUID().uuidString)") ?? .standard)

        _ = RootTabView(composition: composition)
        _ = composition.todayScreen(openEat: {})
        _ = composition.trainScreen()
        _ = composition.eatScreen()
        _ = composition.trendsScreen()
    }

    /// On a simulator with no Worker origin, no export folder and no Watch, the report says
    /// so rather than the build looking identical to a fully wired device.
    @Test("an unconfigured device reports what it could not wire")
    func startupReportIsHonest() {
        let composition = AppComposition(defaults: UserDefaults(
            suiteName: "ascension.tests.startup.\(UUID().uuidString)") ?? .standard)
        let report = composition.startup

        #expect(report.seedInstalled)
        #expect(report.remote == "not configured" || report.remote == "no worker origin")
        #expect(composition.sync == nil)
        #expect(composition.backgroundSync == nil)
        #expect(!report.heartRateMaximumKnown)
        #expect(report.lines.count == 8)
    }
}
