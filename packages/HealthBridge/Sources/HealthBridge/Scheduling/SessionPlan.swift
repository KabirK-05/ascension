import AscensionCore
import Foundation

/// What the Watch is asked to do, described without WorkoutKit.
///
/// The split is the same one the rest of this module uses: the shape of a session is
/// value logic and is tested on the host, and `WatchSessionScheduler` is the only place
/// that knows WorkoutKit exists. Nothing here starts or records anything — a plan is a
/// prescription handed to Apple's Workout app, which remains the recorder (spec §1).
public struct SessionPlan: Hashable, Sendable {
    public var displayName: String
    public var activity: SessionActivity
    public var location: SessionLocation
    public var blocks: [SessionPlanBlock]

    public init(displayName: String, activity: SessionActivity,
                location: SessionLocation = .indoor, blocks: [SessionPlanBlock]) {
        self.displayName = displayName
        self.activity = activity
        self.location = location
        self.blocks = blocks
    }
}

/// The activity the Watch records the session as. A small closed set: this app only ever
/// prescribes lifting and the incline-walk conditioning the program calls for.
public enum SessionActivity: String, Hashable, Sendable, CaseIterable {
    case traditionalStrengthTraining
    case walking
}

public enum SessionLocation: String, Hashable, Sendable, CaseIterable {
    case indoor
    case outdoor
}

/// One interval block: its steps, repeated `iterations` times.
public struct SessionPlanBlock: Hashable, Sendable {
    public var steps: [SessionPlanStep]
    public var iterations: Int

    public init(steps: [SessionPlanStep], iterations: Int = 1) {
        self.steps = steps
        self.iterations = max(1, iterations)
    }
}

/// One step of a block.
public struct SessionPlanStep: Hashable, Sendable {
    public var displayName: String?
    public var purpose: Purpose
    public var goal: SessionGoal
    public var heartRate: SessionHeartRateTarget?

    public enum Purpose: String, Hashable, Sendable, CaseIterable {
        case work
        case recovery
    }

    public init(displayName: String? = nil, purpose: Purpose = .work,
                goal: SessionGoal = .open, heartRate: SessionHeartRateTarget? = nil) {
        self.displayName = displayName
        self.purpose = purpose
        self.goal = goal
        self.heartRate = heartRate
    }
}

/// When a step ends. `open` is a step the user ends themselves, which is what a set of
/// lifting is — the Watch cannot know when the bar is racked.
public enum SessionGoal: Hashable, Sendable {
    case open
    case minutes(Double)
}

/// The heart rate a step asks for.
///
/// `bpmRange` is preferred when the app's own zone bounds are known, because they are the
/// bounds every other number in this app is computed against. `zone` defers to whatever
/// zones the user's Watch holds, which is the only option when ours are unknown.
public enum SessionHeartRateTarget: Hashable, Sendable {
    case zone(Int)
    case bpmRange(ClosedRange<Int>)
}
