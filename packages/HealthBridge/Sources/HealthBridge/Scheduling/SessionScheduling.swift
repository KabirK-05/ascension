import AscensionCore
import Foundation

/// Why a plan could not reach the Watch.
public enum SessionSchedulingError: Error, Hashable, Sendable {
    /// WorkoutKit scheduling does not exist here — every Mac, CI, and a phone with no
    /// paired Watch.
    case schedulingUnavailable
    /// The user has not allowed this app to schedule workouts.
    case notAuthorized
    /// A rest day, or a session with nothing to prescribe.
    case nothingToSchedule
    /// The framework refused. The string is for logs, not for the user.
    case scheduleFailed(String)
}

/// Whether the Watch will accept scheduled workouts from this app.
public enum SessionSchedulingAuthorization: String, Hashable, Sendable, CaseIterable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

/// Sending a planned session to the Apple Watch Workout app.
///
/// The seam exists for the same reason `HealthStore` does: WorkoutKit is iOS-only, so the
/// plan-building logic above it is testable on the host and in CI only if nothing calls
/// the framework directly. It is also the injection point the app shell hands to the
/// features — Today's Send to Watch button and Train's own both end up here.
public protocol SessionScheduling: Sendable {
    var isSupported: Bool { get }
    func requestAuthorization() async -> SessionSchedulingAuthorization

    /// Schedules `plan` to begin at `date`. Scheduling the same session twice replaces
    /// the earlier one rather than stacking two workouts on the Watch.
    func schedule(_ plan: SessionPlan, at date: Date) async throws

    /// Removes anything this app previously scheduled that has not yet started.
    func removeScheduled() async
}

/// The implementation used where WorkoutKit is absent — macOS, CI, previews.
///
/// It refuses rather than pretending to succeed: a Send to Watch that silently did
/// nothing is worse than one that says it could not.
public struct UnavailableSessionScheduler: SessionScheduling {
    public init() {}

    public var isSupported: Bool { false }

    public func requestAuthorization() async -> SessionSchedulingAuthorization { .unavailable }

    public func schedule(_ plan: SessionPlan, at date: Date) async throws {
        throw SessionSchedulingError.schedulingUnavailable
    }

    public func removeScheduled() async {}
}
