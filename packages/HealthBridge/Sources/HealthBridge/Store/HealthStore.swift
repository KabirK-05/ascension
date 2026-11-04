import Foundation

/// A failure that came from the store rather than from this module's logic.
public enum HealthStoreError: Error, Hashable, Sendable {
    /// HealthKit does not exist on this device (every Mac, and CI).
    case healthDataUnavailable
    /// The user refused, or has not yet been asked for, a write scope.
    case writeNotAuthorized(HealthWriteMetric)
    /// The metric cannot be queried the way the caller asked for.
    case unsupportedQuery(HealthMetric)
    /// The underlying framework failed. The string is for logs, not for the user.
    case queryFailed(String)
}

/// An opaque resume point for an anchored query, so a pass reads only what is new.
public struct HealthAnchorToken: Hashable, Sendable {
    public var rawValue: Data

    public init(rawValue: Data) { self.rawValue = rawValue }
}

/// A page of anchored results: what changed, what was removed, and where to resume.
public struct AnchoredWorkouts: Hashable, Sendable {
    public var workouts: [WorkoutRecord]
    public var deletedIds: [UUID]
    public var anchor: HealthAnchorToken?

    public init(workouts: [WorkoutRecord], deletedIds: [UUID] = [],
                anchor: HealthAnchorToken? = nil) {
        self.workouts = workouts
        self.deletedIds = deletedIds
        self.anchor = anchor
    }
}

/// What an observer hands back: the metric that changed, and the acknowledgement iOS
/// insists on receiving once the work is done.
public typealias HealthChangeHandler =
    @Sendable (HealthMetric, @Sendable @escaping () -> Void) -> Void

/// Everything this module needs from HealthKit, and nothing more.
///
/// The seam exists for one reason: HealthKit does not exist on macOS or in CI, so none of
/// the mirror, zone or aggregation logic could be tested if it talked to `HKHealthStore`
/// directly. `HKHealthStoreAdapter` is the thin real implementation; the tests use a fake.
public protocol HealthStore: Sendable {
    var isHealthDataAvailable: Bool { get }

    /// Presents the system sheet. Returns without error even when the user denies
    /// everything — HealthKit treats "asked and refused" as a successful ask.
    func requestAuthorization(read: Set<HealthMetric>, write: Set<HealthWriteMetric>) async throws

    /// Write status is the only authorization HealthKit answers honestly.
    func writeStatus(for metric: HealthWriteMetric) -> WriteAuthorization

    /// Whether the system still needs to ask. HealthKit will not say what was granted,
    /// only whether a prompt is outstanding.
    func authorizationRequestStatus(read: Set<HealthMetric>,
                                    write: Set<HealthWriteMetric>) async throws -> AuthorizationRequest

    /// One number for the window, computed the way the metric's `aggregation` says.
    /// On device this is an `HKStatisticsQuery`; the fake computes it with
    /// `MetricAggregator`, which is the reference definition of each aggregation.
    func statistic(_ metric: HealthMetric, in interval: DateInterval) async throws -> Double?

    func quantitySamples(_ metric: HealthMetric, in interval: DateInterval) async throws -> [QuantityRecord]
    func categorySamples(_ metric: HealthMetric, in interval: DateInterval) async throws -> [CategoryRecord]
    func workouts(in interval: DateInterval) async throws -> [WorkoutRecord]

    /// Heart-rate samples recorded *by* a workout, which is what time-in-zone needs.
    func heartRateSeries(forWorkout id: UUID, in interval: DateInterval) async throws -> [QuantityRecord]

    /// Anchored read for the observer path, so a callback that fires twice for the same
    /// data returns nothing the second time.
    func anchoredWorkouts(since anchor: HealthAnchorToken?) async throws -> AnchoredWorkouts

    func save(_ samples: [WriteSample]) async throws

    /// Registers an observer query. The handler is handed a completion block that **must**
    /// be called, success or failure, or iOS stops delivering updates for that type.
    func startObserving(
        _ metrics: Set<HealthMetric>,
        onChange: @escaping HealthChangeHandler
    ) throws

    func enableBackgroundDelivery(for metrics: Set<HealthMetric>) async throws
    func disableAllBackgroundDelivery() async throws
}
