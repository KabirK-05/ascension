import Foundation
import Testing

@testable import HealthBridge

@Suite("authorization is reported honestly")
struct AuthorizationTests {
    @Test("read access has no granted state, because HealthKit will not say")
    func readAuthorizationCannotClaimAccess() {
        #expect(ReadAuthorization.allCases.count == 2)
        #expect(ReadAuthorization.allCases.contains(.askedButUnknowable))
        #expect(ReadAuthorization.allCases.map(\.rawValue).contains("granted") == false)
    }

    @Test("requesting asks for the whole §6 read map and the narrow write scope")
    func requestCoversTheSpecMap() async throws {
        let store = FakeHealthStore()
        let report = try await HealthAuthorizationCoordinator(store: store).requestAuthorization()

        #expect(store.authorizationAsked.read == Set(HealthMetric.allCases))
        #expect(store.authorizationAsked.read.count == 18)
        #expect(store.authorizationAsked.write == Set(HealthWriteMetric.allCases))
        #expect(report.read == .askedButUnknowable)
        #expect(report.state == .readyWithinUncertainty)
    }

    @Test("before the sheet is shown, the state is 'needs request', not 'denied'")
    func notDeterminedIsNotDenied() async {
        let store = FakeHealthStore()
        store.update { config in
            config.requestStatus = .shouldRequest
            config.writeStatuses = Dictionary(
                uniqueKeysWithValues: HealthWriteMetric.allCases.map { ($0, .notDetermined) })
        }
        let report = await HealthAuthorizationCoordinator(store: store).report()

        #expect(report.read == .notDetermined)
        #expect(report.state == .needsRequest)
        #expect(report.deniedWrites.isEmpty)
        #expect(report.undeterminedWrites.count == 7)
        #expect(report.canWriteSomething == false)
    }

    @Test("a partially granted write scope is its own state")
    func partialGrantIsVisible() async {
        let store = FakeHealthStore()
        store.update { config in
            config.writeStatuses[.dietaryWater] = .denied
            config.writeStatuses[.waistCircumference] = .denied
        }
        let report = await HealthAuthorizationCoordinator(store: store).report()

        #expect(report.state == .partialWriteAccess)
        #expect(report.deniedWrites == [.dietaryWater, .waistCircumference])
        #expect(report.canWriteEverything == false)
        #expect(report.canWriteSomething)
    }

    @Test("every write refused is reported as such")
    func allRefused() async {
        let store = FakeHealthStore()
        store.update { config in
            config.writeStatuses = Dictionary(
                uniqueKeysWithValues: HealthWriteMetric.allCases.map { ($0, .denied) })
        }
        let report = await HealthAuthorizationCoordinator(store: store).report()
        #expect(report.state == .writesRefused)
    }

    @Test("no HealthKit means unavailable, not denied, and no sheet is attempted")
    func unavailableDeviceIsItsOwnState() async throws {
        let store = FakeHealthStore(config: .init(available: false))
        let coordinator = HealthAuthorizationCoordinator(store: store)

        let report = try await coordinator.requestAuthorization()
        #expect(report.state == .unavailable)
        #expect(report.isHealthDataAvailable == false)
        #expect(store.authorizationAsked.read.isEmpty)
    }
}
