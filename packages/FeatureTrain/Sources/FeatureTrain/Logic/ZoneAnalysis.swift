import AscensionCore
import Foundation

/// The time-in-zone breakdown a debrief shows, and the Zone 2 verification spec §F2 asks
/// for: a session that spent more of its time above Zone 2 than in it drifted.
///
/// `HealthBridge` states the same drift rule at the mirror layer. The definition is one
/// line and identical in both places on purpose — it is the rule, not an implementation —
/// and this type exists because the debrief needs the whole breakdown, not just the flag.
public struct ZoneAnalysis: Hashable, Sendable {
    /// Minutes in zones 1 through 5, in order.
    public var minutes: [Double]

    public init(_ zones: TimeInZonesMinutes) {
        self.minutes = [zones.z1, zones.z2, zones.z3, zones.z4, zones.z5]
    }

    public var total: Double { minutes.reduce(0, +) }

    public var isEmpty: Bool { total <= 0 }

    /// The share of counted time a zone held, 0 through 1.
    public func share(ofZone zone: Int) -> Double {
        guard total > 0, (1...minutes.count).contains(zone) else { return 0 }
        return minutes[zone - 1] / total
    }

    public func minutes(inZone zone: Int) -> Double {
        guard (1...minutes.count).contains(zone) else { return 0 }
        return minutes[zone - 1]
    }

    /// The zone that held the most time. `nil` when nothing was counted — a session with
    /// no heart-rate series has no dominant zone, and showing zone 1 would be a lie.
    public var dominantZone: Int? {
        guard let peak = minutes.max(), peak > 0 else { return nil }
        return (minutes.firstIndex(of: peak) ?? 0) + 1
    }

    /// More time above Zone 2 than in it.
    public var driftedAboveZone2: Bool {
        guard total > 0 else { return false }
        return minutes[2] + minutes[3] + minutes[4] > minutes[1]
    }
}
