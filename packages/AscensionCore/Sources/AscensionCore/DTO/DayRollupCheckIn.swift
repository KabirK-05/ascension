import Foundation

/// Soreness across the eight groups the morning check-in asks about.
///
/// Named fields rather than a dictionary: the groups are a closed set, so the shape
/// itself refuses an unknown group.
public struct Soreness: Codable, Hashable, Sendable {
    public var chest: SorenessLevel
    public var back: SorenessLevel
    public var shoulders: SorenessLevel
    public var arms: SorenessLevel
    public var quads: SorenessLevel
    public var hamstrings: SorenessLevel
    public var glutes: SorenessLevel
    public var core: SorenessLevel

    public init(chest: SorenessLevel = .none, back: SorenessLevel = .none,
                shoulders: SorenessLevel = .none, arms: SorenessLevel = .none,
                quads: SorenessLevel = .none, hamstrings: SorenessLevel = .none,
                glutes: SorenessLevel = .none, core: SorenessLevel = .none) {
        self.chest = chest
        self.back = back
        self.shoulders = shoulders
        self.arms = arms
        self.quads = quads
        self.hamstrings = hamstrings
        self.glutes = glutes
        self.core = core
    }

    public func level(for group: MuscleGroup) -> SorenessLevel {
        switch group {
        case .chest: return chest
        case .back: return back
        case .shoulders: return shoulders
        case .arms: return arms
        case .quads: return quads
        case .hamstrings: return hamstrings
        case .glutes: return glutes
        case .core: return core
        }
    }

    public var byGroup: [MuscleGroup: SorenessLevel] {
        Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0, level(for: $0)) })
    }
}

/// The ten-second morning check-in. `energy` is a closed 1–5 scale.
public struct CheckInRollup: Codable, Hashable, Sendable {
    public static let energyRange = 1...5

    public var energy: Int
    public var soreness: Soreness

    public init(energy: Int, soreness: Soreness) {
        self.energy = energy
        self.soreness = soreness
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let energy = try container.decode(Int.self, forKey: .energy)
        guard Self.energyRange.contains(energy) else {
            throw DecodingError.dataCorruptedError(
                forKey: .energy, in: container,
                debugDescription: "energy must be 1–5, found \(energy)")
        }
        self.energy = energy
        self.soreness = try container.decode(Soreness.self, forKey: .soreness)
    }
}

/// Today's readiness score and what to do about it.
public struct ReadinessRollup: Codable, Hashable, Sendable {
    public var score: Int
    public var verdict: ReadinessVerdict
    public var reasons: [String]

    public init(score: Int, verdict: ReadinessVerdict, reasons: [String]) {
        self.score = score
        self.verdict = verdict
        self.reasons = reasons
    }
}

/// The four daily wins behind the consistency grid. `total` is their count.
public struct Wins: Codable, Hashable, Sendable {
    public static let totalRange = 0...4

    public var session: Bool
    public var protein: Bool
    public var steps: Bool
    public var sleep: Bool
    public var total: Int

    /// Builds a `Wins` whose `total` can only be the count of its own flags.
    public init(session: Bool, protein: Bool, steps: Bool, sleep: Bool) {
        self.session = session
        self.protein = protein
        self.steps = steps
        self.sleep = sleep
        self.total = [session, protein, steps, sleep].count { $0 }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let total = try container.decode(Int.self, forKey: .total)
        guard Self.totalRange.contains(total) else {
            throw DecodingError.dataCorruptedError(
                forKey: .total, in: container,
                debugDescription: "wins.total must be 0–4, found \(total)")
        }
        self.session = try container.decode(Bool.self, forKey: .session)
        self.protein = try container.decode(Bool.self, forKey: .protein)
        self.steps = try container.decode(Bool.self, forKey: .steps)
        self.sleep = try container.decode(Bool.self, forKey: .sleep)
        self.total = total
    }
}
