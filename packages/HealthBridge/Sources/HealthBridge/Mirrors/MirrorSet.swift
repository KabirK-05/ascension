import Foundation

/// Everything one mirror pass produced.
public struct MirrorSet: Hashable, Sendable {
    public var workouts: [WorkoutMirror]
    public var nights: [SleepNight]
    public var weights: [WeightPoint]

    public init(workouts: [WorkoutMirror] = [], nights: [SleepNight] = [],
                weights: [WeightPoint] = []) {
        self.workouts = workouts
        self.nights = nights
        self.weights = weights
    }

    public var isEmpty: Bool { workouts.isEmpty && nights.isEmpty && weights.isEmpty }

    /// Folds a later pass into an earlier one. Every collection upserts on its own key —
    /// workout UUID, night date, weight date — so running the same pass twice is a no-op.
    public func merging(_ other: MirrorSet, deletedWorkoutIds: Set<String> = []) -> MirrorSet {
        MirrorSet(
            workouts: WorkoutMirrorBuilder.merging(existing: workouts,
                                                   incoming: other.workouts,
                                                   deletedIds: deletedWorkoutIds),
            nights: SleepNightBuilder.merging(existing: nights, incoming: other.nights),
            weights: WeightPointBuilder.merging(existing: weights, incoming: other.weights))
    }
}
