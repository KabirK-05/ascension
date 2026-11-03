import Foundation

/// Asks for the §6 scopes and reports what came back, with the uncertainty intact.
public struct HealthAuthorizationCoordinator: Sendable {
    private let store: any HealthStore
    private let readScopes: Set<HealthMetric>
    private let writeScopes: Set<HealthWriteMetric>

    public init(store: any HealthStore,
                readScopes: Set<HealthMetric> = HealthScopes.read,
                writeScopes: Set<HealthWriteMetric> = HealthScopes.write) {
        self.store = store
        self.readScopes = readScopes
        self.writeScopes = writeScopes
    }

    /// Presents the sheet if anything is outstanding, then reports. Safe to call on every
    /// launch: HealthKit shows nothing when there is nothing left to ask.
    public func requestAuthorization() async throws -> HealthAuthorizationReport {
        guard store.isHealthDataAvailable else { return unavailableReport }
        try await store.requestAuthorization(read: readScopes, write: writeScopes)
        return await currentReport(afterRequesting: true)
    }

    /// Reports without presenting anything, for a settings screen.
    public func report() async -> HealthAuthorizationReport {
        guard store.isHealthDataAvailable else { return unavailableReport }
        return await currentReport(afterRequesting: false)
    }

    private func currentReport(afterRequesting requested: Bool) async -> HealthAuthorizationReport {
        let request = await requestStatus()
        let writes = writeScopes.reduce(into: [HealthWriteMetric: WriteAuthorization]()) { result, metric in
            result[metric] = store.writeStatus(for: metric)
        }
        // A sheet that has just been dismissed means the user was asked. Before that,
        // "nothing to request" also means they were asked at some earlier launch.
        let asked = requested || request == .unnecessary
        return HealthAuthorizationReport(
            isHealthDataAvailable: true,
            read: asked ? .askedButUnknowable : .notDetermined,
            write: writes,
            request: request)
    }

    private func requestStatus() async -> AuthorizationRequest {
        do {
            return try await store.authorizationRequestStatus(read: readScopes, write: writeScopes)
        } catch {
            return .unknown
        }
    }

    private var unavailableReport: HealthAuthorizationReport {
        HealthAuthorizationReport(
            isHealthDataAvailable: false,
            read: .notDetermined,
            write: writeScopes.reduce(into: [:]) { $0[$1] = .notDetermined },
            request: .unknown)
    }
}
