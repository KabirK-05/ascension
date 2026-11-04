import AscensionCore
import Foundation

/// A fact the engine could show, and how much it weighs on today.
struct ReasonCandidate: Hashable, Sendable {
    /// The sentence shown to the user. A plain fact with units.
    let text: String

    /// `0...1`, where 1 is the most adverse. Drives which two facts survive.
    let severity: Double

    /// Tie-break, so the same inputs always produce the same two reasons in the same
    /// order. Lower wins.
    let priority: Int
}

/// Spec §F5: "every verdict shows its top 2 reasons".
///
/// Reasons are facts with units — `slept 6h10`, `HRV −18% vs baseline` — never advice,
/// never encouragement (`docs/DESIGN_RULES.md` §1). Every signal contributes a candidate
/// whether or not it was measured, so there are always at least two to choose from and
/// an absent reading is itself reportable.
enum ReadinessReasons {
    /// The two facts behind today's verdict, most significant first.
    static func topTwo(input: ReadinessInput,
                       factors: [ScoreFactor],
                       availabilities: [MuscleRegion: RegionAvailability],
                       blocked: [MuscleRegion: RegionBlockReason]) -> [String] {
        let ranked = candidates(input: input, factors: factors,
                                availabilities: availabilities, blocked: blocked)
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.priority < rhs.priority
            }
        return Array(ranked.prefix(2)).map(\.text)
    }

    static func candidates(input: ReadinessInput,
                           factors: [ScoreFactor],
                           availabilities: [MuscleRegion: RegionAvailability],
                           blocked: [MuscleRegion: RegionBlockReason]) -> [ReasonCandidate] {
        var candidates = blockCandidates(availabilities: availabilities, blocked: blocked)
        let byKind = Dictionary(uniqueKeysWithValues: factors.map { ($0.kind, $0) })
        for kind in ScoreFactorKind.allCases {
            guard let factor = byKind[kind] else { continue }
            candidates.append(candidate(for: factor, input: input))
        }
        return candidates
    }

    // MARK: - The constraint

    /// A blocked region outranks every measurement: it is the reason the verdict is what
    /// it is, so it is pinned to maximum severity.
    private static func blockCandidates(
        availabilities: [MuscleRegion: RegionAvailability],
        blocked: [MuscleRegion: RegionBlockReason]
    ) -> [ReasonCandidate] {
        blocked.keys.sorted { $0.rawValue < $1.rawValue }.enumerated().compactMap { index, region in
            guard let reason = blocked[region], let availability = availabilities[region] else {
                return nil
            }
            return ReasonCandidate(text: blockText(region: region, reason: reason,
                                                   availability: availability),
                                   severity: 1,
                                   priority: index)
        }
    }

    private static func blockText(region: MuscleRegion,
                                  reason: RegionBlockReason,
                                  availability: RegionAvailability) -> String {
        switch reason {
        case .sore:
            return "\(Phrase.list(availability.soreGroups.map(\.rawValue))) sore"
        case .withinRecoveryWindow:
            let hours = availability.hoursSinceTrained ?? 0
            return "\(name(of: region)) trained \(Int(hours.rounded())) h ago"
        case .recencyUnknown:
            return "\(name(of: region)) last session not dated"
        }
    }

    private static func name(of region: MuscleRegion) -> String {
        switch region {
        case .upperBody: return "upper body"
        case .lowerBody: return "lower body"
        }
    }

    // MARK: - The measurements

    private static func candidate(for factor: ScoreFactor,
                                  input: ReadinessInput) -> ReasonCandidate {
        // Priorities sit above the block candidates, which occupy 0 upwards, so a
        // constraint always wins a tie.
        let priority = 100 + (ScoreFactorKind.allCases.firstIndex(of: factor.kind) ?? 0)
        guard let value = factor.value else {
            return ReasonCandidate(text: missingText(factor.kind),
                                   severity: 0.5,
                                   priority: priority)
        }
        return ReasonCandidate(text: text(for: factor.kind, input: input),
                               severity: 1 - value,
                               priority: priority)
    }

    /// The wording an absent reading gets, exposed so the tests can assert that every
    /// factor has one.
    static func missingTextForTesting(_ kind: ScoreFactorKind) -> String {
        missingText(kind)
    }

    /// An absent reading sits mid-severity: worth saying, never alarming.
    private static func missingText(_ kind: ScoreFactorKind) -> String {
        switch kind {
        case .sleepDuration: return "no sleep data"
        case .sleepConsistency: return "no bedtime history"
        case .hrv: return "no HRV baseline"
        case .restingHr: return "no resting HR baseline"
        case .yesterdayLoad: return "yesterday's load not measured"
        case .soreness: return "no check-in"
        case .energy: return "no energy rating"
        }
    }

    private static func text(for kind: ScoreFactorKind, input: ReadinessInput) -> String {
        switch kind {
        case .sleepDuration: return sleepText(input)
        case .sleepConsistency: return consistencyText(input)
        case .hrv: return hrvText(input)
        case .restingHr: return restingHrText(input)
        case .yesterdayLoad: return loadText(input)
        case .soreness: return sorenessText(input)
        case .energy: return energyText(input)
        }
    }

    private static func sleepText(_ input: ReadinessInput) -> String {
        "slept \(Phrase.duration(minutes: input.sleep.asleepMinutes ?? 0))"
    }

    private static func consistencyText(_ input: ReadinessInput) -> String {
        let minutes = Int((input.sleep.consistencySd7Minutes ?? 0).rounded())
        return "bedtime varies \(minutes) min"
    }

    /// `HRV −18% vs baseline`, or `HRV near baseline` inside ±3%, which is noise.
    private static func hrvText(_ input: ReadinessInput) -> String {
        guard let measured = input.vitals.hrvSdnnMs,
              let baseline = input.baselines.hrvSdnnMs, baseline > 0 else {
            return missingText(.hrv)
        }
        let delta = (measured - baseline) / baseline
        guard abs(delta) >= 0.03 else { return "HRV near baseline" }
        return "HRV \(Phrase.signedPercent(delta)) vs baseline"
    }

    private static func restingHrText(_ input: ReadinessInput) -> String {
        guard let measured = input.vitals.restingHrBpm,
              let baseline = input.baselines.restingHrBpm else {
            return missingText(.restingHr)
        }
        let delta = Int((Double(measured) - baseline).rounded())
        return "resting HR \(measured) bpm, \(Phrase.signed(delta)) vs baseline"
    }

    private static func loadText(_ input: ReadinessInput) -> String {
        guard let load = input.yesterdayLoadAu else { return missingText(.yesterdayLoad) }
        guard load > 0 else { return "no training load yesterday" }
        guard let baseline = input.baselines.trainingDayLoadAu, baseline > 0 else {
            return "load \(Int(load.rounded())) au yesterday"
        }
        let multiple = Phrase.decimal(load / baseline)
        return "load \(Int(load.rounded())) au yesterday, \(multiple)× typical"
    }

    /// `quads sore`, `back and quads sore`, `back mild`, or `no soreness reported`.
    private static func sorenessText(_ input: ReadinessInput) -> String {
        guard let soreness = input.checkIn?.soreness else { return missingText(.soreness) }
        let byGroup = MuscleGroup.allCases.map { ($0, soreness.level(for: $0)) }
        let sore = byGroup.filter { $0.1 == .sore }.map(\.0.rawValue)
        if !sore.isEmpty { return "\(Phrase.list(sore)) sore" }
        let mild = byGroup.filter { $0.1 == .mild }.map(\.0.rawValue)
        if !mild.isEmpty { return "\(Phrase.list(mild)) mild" }
        return "no soreness reported"
    }

    private static func energyText(_ input: ReadinessInput) -> String {
        guard let energy = input.checkIn?.energy else { return missingText(.energy) }
        return "energy \(energy) of \(CheckInRollup.energyRange.upperBound)"
    }
}
