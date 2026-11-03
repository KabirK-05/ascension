import Foundation

/// Write ("share") authorization, which HealthKit does report truthfully.
public enum WriteAuthorization: String, Codable, Hashable, Sendable, CaseIterable {
    case notDetermined
    case denied
    case granted
}

/// Read authorization, which HealthKit deliberately does **not** report.
///
/// There is no `granted` case and there never can be one. Apple hides read denial so an
/// app cannot infer a condition from the absence of data, which means "you denied heart
/// rate" and "you have never recorded heart rate" are the same answer. Modelling a
/// `granted` case here would be a lie that the rest of the app would then rely on.
public enum ReadAuthorization: String, Codable, Hashable, Sendable, CaseIterable {
    /// The sheet has not been shown for this scope yet.
    case notDetermined
    /// The sheet has been shown. Whether this scope was granted is unknowable; an empty
    /// read means "no data or no permission".
    case askedButUnknowable
}

/// Whether the system sheet still has something to ask about.
public enum AuthorizationRequest: String, Codable, Hashable, Sendable, CaseIterable {
    case shouldRequest
    case unnecessary
    case unknown
}

/// The whole truth about what the app may do, with the uncertainty left in.
///
/// Three honest states come out of this: HealthKit is missing entirely, the user has not
/// been asked, or the user has been asked and some writes may still be denied. A screen
/// that wants to say "Health access granted" cannot, and that is the point.
public struct HealthAuthorizationReport: Hashable, Sendable {
    public var isHealthDataAvailable: Bool
    public var read: ReadAuthorization
    public var write: [HealthWriteMetric: WriteAuthorization]
    public var request: AuthorizationRequest

    public init(isHealthDataAvailable: Bool, read: ReadAuthorization,
                write: [HealthWriteMetric: WriteAuthorization],
                request: AuthorizationRequest) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.read = read
        self.write = write
        self.request = request
    }

    /// Write scopes the user has refused. Empty is not proof of consent — a scope that
    /// was never asked about is `notDetermined`, not `granted`.
    public var deniedWrites: Set<HealthWriteMetric> {
        Set(write.filter { $0.value == .denied }.keys)
    }

    public var grantedWrites: Set<HealthWriteMetric> {
        Set(write.filter { $0.value == .granted }.keys)
    }

    public var undeterminedWrites: Set<HealthWriteMetric> {
        Set(write.filter { $0.value == .notDetermined }.keys)
    }

    /// True when at least one write scope is granted and none is outstanding — the only
    /// state in which the nutrition write-back can be relied on for every field.
    public var canWriteEverything: Bool {
        !write.isEmpty && write.values.allSatisfy { $0 == .granted }
    }

    public var canWriteSomething: Bool { !grantedWrites.isEmpty }

    /// What the app should do next, which is all a caller actually needs.
    public var state: HealthAccessState {
        guard isHealthDataAvailable else { return .unavailable }
        if request == .shouldRequest || read == .notDetermined { return .needsRequest }
        if canWriteEverything { return .readyWithinUncertainty }
        if canWriteSomething { return .partialWriteAccess }
        return .writesRefused
    }
}

/// The four states worth branching on. Named so no caller is tempted to say "authorized".
public enum HealthAccessState: String, Hashable, Sendable, CaseIterable {
    /// No HealthKit on this device. Nothing to offer the user.
    case unavailable
    /// The sheet has not been shown, or has something left to ask.
    case needsRequest
    /// Writes are all granted; reads may silently return nothing regardless.
    case readyWithinUncertainty
    /// Some writes granted, some refused. Logging works partially and must say so.
    case partialWriteAccess
    /// Every write refused. Reads may still work, unknowably.
    case writesRefused
}
