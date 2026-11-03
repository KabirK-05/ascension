import AscensionCore
import Foundation

/// What a region's recovery looks like right now.
public struct RegionAvailability: Hashable, Sendable {
    public let region: MuscleRegion

    /// Hours since the region was last loaded. `nil` means it was not trained inside the
    /// history the caller supplied.
    public let hoursSinceTrained: Double?

    /// `false` when a last-trained stamp existed but could not be read.
    public let recencyKnown: Bool

    /// Groups in this region the check-in marked `sore`.
    public let soreGroups: [MuscleGroup]

    /// Groups in this region the check-in marked `mild`.
    public let mildGroups: [MuscleGroup]

    /// `true` when the region was trained less than ``ReadinessThresholds/recoveryHours``
    /// ago, or when its recency cannot be read at all.
    public var isWithinRecoveryWindow: Bool {
        guard recencyKnown else { return true }
        guard let hoursSinceTrained else { return false }
        return hoursSinceTrained < ReadinessThresholds.recoveryHours
    }

    public var isSore: Bool { !soreGroups.isEmpty }

    /// The spec §F5 hard rule, in one expression: never a region inside the recovery
    /// window, never a sore region.
    public var isTrainable: Bool { !isWithinRecoveryWindow && !isSore }

    public var blockReason: RegionBlockReason? {
        if isSore { return .sore }
        if !recencyKnown { return .recencyUnknown }
        if isWithinRecoveryWindow { return .withinRecoveryWindow }
        return nil
    }
}

/// The spec §F5 constraint — "never recommend training a muscle group that was trained
/// < 48 h ago or is marked sore" — and the swap that constraint implies.
///
/// Nothing else in the engine is allowed to decide what may be trained; the score only
/// decides how hard.
public enum SessionLegality {
    /// Which check-in groups make up each region.
    ///
    /// `core` belongs to neither. It is accessory work in every session of the program
    /// (spec §3 puts a plank in Lower A and core work in Lower B), so letting a sore core
    /// block a whole region would veto nearly every training day. Core soreness instead
    /// caps the verdict at `capIntensity` — see ``ReadinessEngine``.
    public static func groups(in region: MuscleRegion) -> [MuscleGroup] {
        switch region {
        case .upperBody: return [.chest, .back, .shoulders, .arms]
        case .lowerBody: return [.quads, .hamstrings, .glutes]
        }
    }

    /// Groups that belong to no region and so never block one.
    public static let unregionedGroups: [MuscleGroup] = [.core]

    /// ``RegionAvailability`` for one region, read off the input.
    public static func availability(of region: MuscleRegion,
                                    input: ReadinessInput) -> RegionAvailability {
        let soreness = input.checkIn?.soreness
        let members = groups(in: region)
        let sore = soreness.map { levels in members.filter { levels.level(for: $0) == .sore } } ?? []
        let mild = soreness.map { levels in members.filter { levels.level(for: $0) == .mild } } ?? []

        guard let stamp = input.lastTrainedAt[region] else {
            return RegionAvailability(region: region, hoursSinceTrained: nil, recencyKnown: true,
                                      soreGroups: sore, mildGroups: mild)
        }
        guard let hours = input.clock.hoursSince(stamp) else {
            return RegionAvailability(region: region, hoursSinceTrained: nil, recencyKnown: false,
                                      soreGroups: sore, mildGroups: mild)
        }
        return RegionAvailability(region: region, hoursSinceTrained: hours, recencyKnown: true,
                                  soreGroups: sore, mildGroups: mild)
    }

    /// ``RegionAvailability`` for every region.
    public static func availabilities(input: ReadinessInput) -> [MuscleRegion: RegionAvailability] {
        var result: [MuscleRegion: RegionAvailability] = [:]
        for region in MuscleRegion.allCases {
            result[region] = availability(of: region, input: input)
        }
        return result
    }

    /// Whether every region a session loads may be trained.
    public static func isLegal(_ kind: SessionKind,
                               availabilities: [MuscleRegion: RegionAvailability]) -> Bool {
        kind.trainedRegions.allSatisfy { availabilities[$0]?.isTrainable ?? true }
    }

    /// Regions of `kind` that may not be trained, and why.
    public static func blockedRegions(
        of kind: SessionKind,
        availabilities: [MuscleRegion: RegionAvailability]
    ) -> [MuscleRegion: RegionBlockReason] {
        var blocked: [MuscleRegion: RegionBlockReason] = [:]
        for region in kind.trainedRegions {
            if let reason = availabilities[region]?.blockReason {
                blocked[region] = reason
            }
        }
        return blocked
    }

    /// The session to do instead of `planned`, or `nil` when there is none.
    ///
    /// Only *lifting* sessions qualify: a candidate must load at least one region, and
    /// every region it loads must be trainable. A program whose only remaining option is
    /// conditioning has no swap — that case is active recovery, which is the reading that
    /// trains less (spec §F5 offers no "do cardio instead" verdict).
    ///
    /// Deterministic: candidates are ranked by how long their least-recently-trained
    /// region has had to recover, then by the declaration order of ``SessionKind``.
    public static func swap(for planned: SessionKind?,
                            among programSessions: Set<SessionKind>,
                            availabilities: [MuscleRegion: RegionAvailability]) -> SessionKind? {
        let order = SessionKind.allCases
        let candidates = programSessions.filter { kind in
            kind != planned
                && kind.isTrainingDay
                && !kind.trainedRegions.isEmpty
                && isLegal(kind, availabilities: availabilities)
        }
        return candidates.min { lhs, rhs in
            let lhsRest = restedness(of: lhs, availabilities: availabilities)
            let rhsRest = restedness(of: rhs, availabilities: availabilities)
            if lhsRest != rhsRest { return lhsRest > rhsRest }
            let lhsIndex = order.firstIndex(of: lhs) ?? order.count
            let rhsIndex = order.firstIndex(of: rhs) ?? order.count
            return lhsIndex < rhsIndex
        }
    }

    /// Hours of recovery the least-recovered region of `kind` has had. A region never
    /// trained counts as maximally recovered.
    private static func restedness(of kind: SessionKind,
                                   availabilities: [MuscleRegion: RegionAvailability]) -> Double {
        let hours = kind.trainedRegions.map { region -> Double in
            guard let availability = availabilities[region] else { return .greatestFiniteMagnitude }
            return availability.hoursSinceTrained ?? .greatestFiniteMagnitude
        }
        return hours.min() ?? .greatestFiniteMagnitude
    }
}
