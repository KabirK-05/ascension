import AscensionCore
import Foundation

#if canImport(WorkoutKit) && canImport(HealthKit)
import HealthKit
import WorkoutKit

/// The real scheduler: the only type in this package that imports WorkoutKit.
///
/// This is the one place in the product that creates a workout, and it creates a *plan*,
/// not a session — `HKWorkoutSession` appears nowhere in this repository and must not
/// (spec §1). The Watch Workout app executes and records; this hands it the prescription.
public struct WatchSessionScheduler: SessionScheduling {
    public init() {}

    public var isSupported: Bool { WorkoutKit.WorkoutScheduler.isSupported }

    public func requestAuthorization() async -> SessionSchedulingAuthorization {
        guard isSupported else { return .unavailable }
        switch await WorkoutKit.WorkoutScheduler.shared.requestAuthorization() {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public func schedule(_ plan: SessionPlan, at date: Date) async throws {
        guard isSupported else { throw SessionSchedulingError.schedulingUnavailable }
        guard !plan.blocks.isEmpty else { throw SessionSchedulingError.nothingToSchedule }
        guard await requestAuthorization() == .authorized else {
            throw SessionSchedulingError.notAuthorized
        }
        // The same session scheduled twice should replace, not stack. WorkoutKit keys
        // nothing for us, so the app's own earlier plans go first.
        await removeScheduled()
        let components = Self.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        await WorkoutKit.WorkoutScheduler.shared.schedule(
            WorkoutKit.WorkoutPlan(.custom(plan.customWorkout)), at: components)
    }

    public func removeScheduled() async {
        guard isSupported else { return }
        let now = Date()
        for workout in await WorkoutKit.WorkoutScheduler.shared.scheduledWorkouts {
            guard let start = Self.calendar.date(from: workout.date), start > now else { continue }
            await WorkoutKit.WorkoutScheduler.shared.remove(workout.plan, at: workout.date)
        }
    }

    /// The user's own calendar: a session is scheduled for a wall-clock time on a day,
    /// which is what `DateComponents` means to WorkoutKit.
    private static var calendar: Calendar { Calendar.current }
}

extension SessionPlan {
    /// The WorkoutKit shape of this plan.
    var customWorkout: CustomWorkout {
        CustomWorkout(activity: activity.workoutActivityType,
                      location: location.sessionLocation,
                      displayName: displayName,
                      blocks: blocks.map(\.intervalBlock))
    }
}

extension SessionPlanBlock {
    var intervalBlock: IntervalBlock {
        IntervalBlock(steps: steps.map(\.intervalStep), iterations: iterations)
    }
}

extension SessionPlanStep {
    var intervalStep: IntervalStep {
        IntervalStep(purpose.intervalPurpose, goal: goal.workoutGoal, alert: heartRate?.workoutAlert)
    }
}

extension SessionPlanStep.Purpose {
    var intervalPurpose: IntervalStep.Purpose {
        switch self {
        case .work: return .work
        case .recovery: return .recovery
        }
    }
}

extension SessionGoal {
    var workoutGoal: WorkoutGoal {
        switch self {
        case .open: return .open
        case .minutes(let minutes): return .time(minutes, .minutes)
        }
    }
}

extension SessionHeartRateTarget {
    /// WorkoutKit takes a frequency, and `UnitFrequency` has no beats-per-minute member,
    /// so bpm is expressed in its SI equivalent: 60 bpm is 1 Hz.
    static func hertz(_ bpm: Int) -> Measurement<UnitFrequency> {
        Measurement(value: Double(bpm) / 60, unit: .hertz)
    }

    var workoutAlert: (any WorkoutAlert)? {
        switch self {
        case .zone(let zone):
            return HeartRateZoneAlert(zone: zone)
        case .bpmRange(let range):
            return HeartRateRangeAlert(target: Self.hertz(range.lowerBound)...Self.hertz(range.upperBound))
        }
    }
}

extension SessionActivity {
    var workoutActivityType: HKWorkoutActivityType {
        switch self {
        case .traditionalStrengthTraining: return .traditionalStrengthTraining
        case .walking: return .walking
        }
    }
}

extension SessionLocation {
    var sessionLocation: HKWorkoutSessionLocationType {
        switch self {
        case .indoor: return .indoor
        case .outdoor: return .outdoor
        }
    }
}
#endif
