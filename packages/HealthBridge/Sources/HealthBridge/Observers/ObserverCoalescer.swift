import Foundation

/// Keeps one pass per metric running at a time, with at most one queued behind it.
///
/// Three background wakes landing while a mirror pass is mid-flight should produce one
/// more pass, not three. Without this the passes interleave and race each other for the
/// same anchor.
public struct ObserverCoalescer: Hashable, Sendable {
    public enum Admission: Hashable, Sendable {
        /// Nothing is running for this metric; start now.
        case start
        /// A pass is already running; it will run once more when it finishes.
        case queued
    }

    private var running: Set<HealthMetric> = []
    private var pending: Set<HealthMetric> = []

    public init() {}

    public mutating func admit(_ metric: HealthMetric) -> Admission {
        guard running.contains(metric) else {
            running.insert(metric)
            return .start
        }
        pending.insert(metric)
        return .queued
    }

    /// Call when a pass finishes. `true` means run it again for the work that arrived
    /// while it was busy.
    public mutating func finish(_ metric: HealthMetric) -> Bool {
        if pending.remove(metric) != nil { return true }
        running.remove(metric)
        return false
    }

    public func isRunning(_ metric: HealthMetric) -> Bool { running.contains(metric) }
    public func isPending(_ metric: HealthMetric) -> Bool { pending.contains(metric) }
}
