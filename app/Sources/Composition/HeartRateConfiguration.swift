import Foundation
import HealthBridge

/// The heart-rate zones time-in-zone and the Zone 2 target are measured against.
///
/// Nothing in the contract supplies them. `goalSettings` holds height and goal weight and
/// deliberately **no date of birth** — `docs/TECH_STACK.md` §2.6 keeps the Worker free of
/// anything identifying — so there is no age to run Tanaka's formula on and no stored
/// maximum. ASC-5 chose the formula and left the input to the shell.
///
/// So this reads a maximum the user can set (Settings, ASC-16) and otherwise answers `nil`.
/// `nil` is honest and has two visible consequences, both of them documented behaviour
/// rather than silent wrongness:
///
/// - `WorkoutMirror.timeInZones` comes back empty, so §F2's Zone 2 drift check has nothing
///   to flag.
/// - `SessionPlanBuilder` falls back to the Watch's own zone 2 instead of this app's bpm
///   bounds, which is the fallback it was written with.
struct HeartRateConfiguration: Sendable {
    static let maximumKey = "ascension.heartRate.maxBpm"

    /// Plausible human maxima. A stored value outside this is ignored rather than used to
    /// compute five nonsense zone boundaries.
    static let plausible: ClosedRange<Double> = 120...220

    let maximumBpm: Double?

    init(maximumBpm: Double?) {
        self.maximumBpm = maximumBpm
    }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.double(forKey: Self.maximumKey)
        self.maximumBpm = Self.plausible.contains(stored) ? stored : nil
    }

    var zones: HeartRateZones? {
        maximumBpm.map { HeartRateZones.percentOfMax($0) }
    }
}
