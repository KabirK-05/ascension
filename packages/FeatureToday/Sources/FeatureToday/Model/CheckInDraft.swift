import AscensionCore
import Foundation

/// The morning check-in while it is being filled in (spec §F4).
///
/// Every group starts at `none`, which is the whole design: the common morning is
/// *nothing is sore*, so it costs no taps at all and only the exceptions are touched.
/// One tap moves a group on by one — `none` → `mild` → `sore` → `none` — which keeps
/// eight groups × three states at eight tap targets rather than twenty-four.
public struct CheckInDraft: Hashable, Sendable {
    public private(set) var soreness: Soreness

    public init(soreness: Soreness = Soreness()) {
        self.soreness = soreness
    }

    public func level(for group: MuscleGroup) -> SorenessLevel {
        soreness.level(for: group)
    }

    /// One tap on a group.
    public mutating func cycle(_ group: MuscleGroup) {
        set(Self.next(after: level(for: group)), for: group)
    }

    public mutating func set(_ level: SorenessLevel, for group: MuscleGroup) {
        switch group {
        case .chest: soreness.chest = level
        case .back: soreness.back = level
        case .shoulders: soreness.shoulders = level
        case .arms: soreness.arms = level
        case .quads: soreness.quads = level
        case .hamstrings: soreness.hamstrings = level
        case .glutes: soreness.glutes = level
        case .core: soreness.core = level
        }
    }

    /// The contract value this draft commits to, or `nil` when `energy` falls outside
    /// the closed 1–5 scale `docs/EXPORT_SCHEMA.md` §1 fixes. The check-in is refused
    /// rather than clamped: a number the user did not choose is not their check-in.
    public func rollup(energy: Int) -> CheckInRollup? {
        guard CheckInRollup.energyRange.contains(energy) else { return nil }
        return CheckInRollup(energy: energy, soreness: soreness)
    }

    static func next(after level: SorenessLevel) -> SorenessLevel {
        switch level {
        case .none: return .mild
        case .mild: return .sore
        case .sore: return .none
        }
    }
}

/// How far a committed check-in has got.
public enum CheckInStatus: Hashable, Sendable {
    case editing
    case saving
    /// The save threw. The controls stay as they were and a `Retry` control appears —
    /// a failure is a control, not a sentence (`docs/DESIGN_RULES.md` §1.4).
    case failed
}

/// The check-in being filled in on this screen, and how far its save has got.
public struct CheckInState: Hashable, Sendable {
    public var draft: CheckInDraft
    public var status: CheckInStatus
    /// The energy last tapped, kept so a failed save has something to retry.
    public var energy: Int?

    public init(draft: CheckInDraft = CheckInDraft(),
                status: CheckInStatus = .editing,
                energy: Int? = nil) {
        self.draft = draft
        self.status = status
        self.energy = energy
    }
}

/// Where a committed check-in goes.
///
/// A protocol in this package rather than a dependency: `FeatureToday` composes
/// `AscensionCore`, `AscensionEngines` and `DesignSystem` and nothing else, so SwiftData,
/// HealthKit and the sync client all stay on the app shell's side of this one method.
/// Injecting nothing is a valid wiring — the check-in then lives for the session only,
/// which is exactly what a preview and the first launch want.
public protocol CheckInStore: Sendable {
    func save(_ checkIn: CheckInRollup, on date: CalendarDate) async throws
}
