import AscensionCore
import Foundation

/// How much of the score was actually measured.
///
/// Spec §F5 requires a missing input to narrow confidence rather than produce a wrong
/// confident verdict, so this travels beside the score and `low` holds the verdict back
/// from `trainAsPlanned` (see ``ReadinessEngine``).
public enum ReadinessConfidence: String, Codable, Hashable, Sendable, CaseIterable {
    case high
    case moderate
    case low
}

/// Why a region may not be trained today.
public enum RegionBlockReason: String, Codable, Hashable, Sendable, CaseIterable {
    /// Trained less than 48 h ago.
    case withinRecoveryWindow

    /// A group in the region is marked `sore` in the morning check-in.
    case sore

    /// A last-trained stamp exists but could not be read, so recency is unknown. Treated
    /// as "too soon", because guessing the other way would recommend training.
    case recencyUnknown
}

/// The engine's answer: a score, what to do about it, and the two facts behind it.
public struct ReadinessAssessment: Hashable, Sendable {
    /// `0...100`, always.
    public let score: Int

    public let verdict: ReadinessVerdict

    /// Exactly two plain facts with units, most significant first. Never advice.
    public let reasons: [String]

    public let confidence: ReadinessConfidence

    /// Share of the score's weight that came from a real measurement, `0...1`.
    public let coverage: Double

    /// The session to do instead. Non-`nil` exactly when `verdict == .swapSession`, and
    /// guaranteed legal under the same 48 h and soreness rules that blocked the plan.
    public let suggestedSession: SessionKind?

    /// Why each blocked region is blocked. Empty when the plan is clear to run.
    public let blockedRegions: [MuscleRegion: RegionBlockReason]

    public init(score: Int, verdict: ReadinessVerdict, reasons: [String],
                confidence: ReadinessConfidence, coverage: Double,
                suggestedSession: SessionKind?,
                blockedRegions: [MuscleRegion: RegionBlockReason]) {
        self.score = score
        self.verdict = verdict
        self.reasons = reasons
        self.confidence = confidence
        self.coverage = coverage
        self.suggestedSession = suggestedSession
        self.blockedRegions = blockedRegions
    }

    /// The subset the contract syncs (`docs/EXPORT_SCHEMA.md` §1).
    public var rollup: ReadinessRollup {
        ReadinessRollup(score: score, verdict: verdict, reasons: reasons)
    }
}

/// Every number the readiness rules turn on, in one place.
///
/// Named rather than inline so a test can sit exactly on a boundary and so a change to a
/// rule is a one-line diff that the suite immediately argues with.
public enum ReadinessThresholds {
    /// Spec §F5: a muscle group trained less sharply recently than this may not be
    /// recommended. The comparison is `>=`, so exactly 48 h is trainable.
    public static let recoveryHours: Double = 48

    /// At or above this score the plan runs untouched.
    public static let trainAsPlannedScore = 75

    /// Below this score nothing is trained, whatever the plan says.
    public static let activeRecoveryScore = 40

    /// Coverage at or above this is `high` confidence.
    public static let highCoverage: Double = 0.8

    /// Coverage at or above this is `moderate`; below it, `low`.
    public static let moderateCoverage: Double = 0.5

    /// Score given when nothing at all was measured: the midpoint, which lands in the
    /// `capIntensity` band and carries `low` confidence.
    public static let unmeasuredScore = 50
}
