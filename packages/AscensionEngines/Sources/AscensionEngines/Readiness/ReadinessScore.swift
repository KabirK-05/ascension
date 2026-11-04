import AscensionCore
import Foundation

/// One contribution to the readiness score.
///
/// `value` is `0...1` (0 = worst, 1 = best) or `nil` for *not measured*. An unmeasured
/// factor is removed from both halves of the weighted mean rather than scored as zero,
/// which is the whole mechanism behind "never treat a `null` measurement as zero".
struct ScoreFactor: Hashable, Sendable {
    let kind: ScoreFactorKind
    let weight: Double
    let value: Double?

    var isMeasured: Bool { value != nil }
}

/// The seven signals spec §F5 lists, in the order they are weighted.
enum ScoreFactorKind: String, Hashable, Sendable, CaseIterable {
    case sleepDuration
    case hrv
    case restingHr
    case soreness
    case sleepConsistency
    case yesterdayLoad
    case energy

    /// Share of a fully-measured score. These sum to 100.
    var weight: Double {
        switch self {
        case .sleepDuration: return 25
        case .hrv: return 25
        case .restingHr: return 15
        case .soreness: return 10
        case .sleepConsistency: return 10
        case .yesterdayLoad: return 10
        case .energy: return 5
        }
    }
}

/// The score half of the engine: seven weighted factors, each `0...1`.
enum ReadinessScore {
    /// The factors, in a fixed order, measured or not.
    static func factors(for input: ReadinessInput) -> [ScoreFactor] {
        ScoreFactorKind.allCases.map { kind in
            ScoreFactor(kind: kind, weight: kind.weight, value: value(of: kind, input: input))
        }
    }

    /// `0...100`, together with the share of weight that was measured.
    static func score(from factors: [ScoreFactor]) -> (score: Int, coverage: Double) {
        let measured = factors.filter(\.isMeasured)
        let presentWeight = measured.reduce(0) { $0 + $1.weight }
        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        guard presentWeight > 0, totalWeight > 0 else {
            return (ReadinessThresholds.unmeasuredScore, 0)
        }
        let weighted = measured.reduce(0.0) { $0 + $1.weight * ($1.value ?? 0) }
        let raw = 100 * weighted / presentWeight
        return (clampScore(raw), presentWeight / totalWeight)
    }

    static func confidence(coverage: Double) -> ReadinessConfidence {
        if coverage >= ReadinessThresholds.highCoverage { return .high }
        if coverage >= ReadinessThresholds.moderateCoverage { return .moderate }
        return .low
    }

    private static func clampScore(_ raw: Double) -> Int {
        min(100, max(0, Int(raw.rounded())))
    }

    private static func value(of kind: ScoreFactorKind, input: ReadinessInput) -> Double? {
        switch kind {
        case .sleepDuration: return sleepDuration(input)
        case .sleepConsistency: return sleepConsistency(input)
        case .hrv: return hrv(input)
        case .restingHr: return restingHr(input)
        case .yesterdayLoad: return yesterdayLoad(input)
        case .soreness: return soreness(input)
        case .energy: return energy(input)
        }
    }

    /// Full marks at the sleep target (7.5 h by default), nothing at 70% of it (5h15).
    private static func sleepDuration(_ input: ReadinessInput) -> Double? {
        guard let asleep = input.sleep.asleepMinutes, input.targets.sleepMinutes > 0 else {
            return nil
        }
        let ratio = Double(asleep) / Double(input.targets.sleepMinutes)
        return ramp(ratio, worst: 0.7, best: 1.0)
    }

    /// Bedtime standard deviation over 7 days: full marks at 30 min or tighter, nothing
    /// at 90 min or looser.
    private static func sleepConsistency(_ input: ReadinessInput) -> Double? {
        guard let deviation = input.sleep.consistencySd7Minutes else { return nil }
        return ramp(deviation, worst: 90, best: 30)
    }

    /// Full marks at 5% above the 30-day baseline, nothing at 20% below it.
    private static func hrv(_ input: ReadinessInput) -> Double? {
        guard let measured = input.vitals.hrvSdnnMs,
              let baseline = input.baselines.hrvSdnnMs, baseline > 0 else { return nil }
        return ramp((measured - baseline) / baseline, worst: -0.20, best: 0.05)
    }

    /// Full marks at or below baseline, nothing at 8 bpm above it.
    private static func restingHr(_ input: ReadinessInput) -> Double? {
        guard let measured = input.vitals.restingHrBpm,
              let baseline = input.baselines.restingHrBpm, baseline > 0 else { return nil }
        return ramp(Double(measured) - baseline, worst: 8, best: 0)
    }

    /// Full marks at or below a typical training day's load, nothing at twice it.
    private static func yesterdayLoad(_ input: ReadinessInput) -> Double? {
        guard let load = input.yesterdayLoadAu,
              let baseline = input.baselines.trainingDayLoadAu, baseline > 0 else { return nil }
        return ramp(load / baseline, worst: 2.0, best: 1.0)
    }

    /// Each sore group costs 0.3, each mild group 0.1, floored at zero.
    ///
    /// The hard constraint already refuses to train a sore region, so this term is about
    /// whole-body fatigue rather than legality.
    private static func soreness(_ input: ReadinessInput) -> Double? {
        guard let soreness = input.checkIn?.soreness else { return nil }
        let levels = MuscleGroup.allCases.map { soreness.level(for: $0) }
        let penalty = levels.reduce(0.0) { total, level in
            switch level {
            case .sore: return total + 0.3
            case .mild: return total + 0.1
            case .none: return total
            }
        }
        return max(0, 1 - penalty)
    }

    /// The 1–5 check-in scale, mapped onto `0...1`.
    private static func energy(_ input: ReadinessInput) -> Double? {
        guard let energy = input.checkIn?.energy else { return nil }
        let span = Double(CheckInRollup.energyRange.upperBound - CheckInRollup.energyRange.lowerBound)
        guard span > 0 else { return nil }
        let offset = Double(energy - CheckInRollup.energyRange.lowerBound)
        return min(1, max(0, offset / span))
    }

    /// Linear interpolation from `worst` (→ 0) to `best` (→ 1), clamped at both ends.
    /// `worst` may be greater than `best`, which is how "lower is better" metrics are
    /// expressed.
    static func ramp(_ measured: Double, worst: Double, best: Double) -> Double {
        guard worst != best else { return measured >= best ? 1 : 0 }
        let fraction = (measured - worst) / (best - worst)
        return min(1, max(0, fraction))
    }
}
