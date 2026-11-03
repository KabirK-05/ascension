import AscensionCore
import Foundation

/// This session against the last one of the same kind (spec §F2: "6 min longer,
/// HR avg −3 bpm").
///
/// Deltas only. A field is `nil` when either session is missing it, because a delta
/// against an absent measurement is not zero.
public struct SessionComparison: Hashable, Sendable {
    public var previous: CompletedSession
    public var durationMinutes: Int
    public var activeEnergyKcal: Int?
    public var hrAvgBpm: Int?
    public var hrMaxBpm: Int?

    public init(previous: CompletedSession, durationMinutes: Int,
                activeEnergyKcal: Int? = nil, hrAvgBpm: Int? = nil, hrMaxBpm: Int? = nil) {
        self.previous = previous
        self.durationMinutes = durationMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
    }

    public static func between(_ session: CompletedSession,
                               and previous: CompletedSession) -> SessionComparison {
        SessionComparison(
            previous: previous,
            durationMinutes: session.durationMinutes - previous.durationMinutes,
            activeEnergyKcal: delta(session.activeEnergyKcal, previous.activeEnergyKcal),
            hrAvgBpm: delta(session.hrAvgBpm, previous.hrAvgBpm),
            hrMaxBpm: delta(session.hrMaxBpm, previous.hrMaxBpm))
    }

    private static func delta(_ later: Int?, _ earlier: Int?) -> Int? {
        guard let later, let earlier else { return nil }
        return later - earlier
    }

    private static func delta(_ later: Double?, _ earlier: Double?) -> Int? {
        guard let later, let earlier else { return nil }
        return Int((later - earlier).rounded())
    }
}

extension CompletedSession {
    /// The most recent session of the same activity type before this one.
    ///
    /// Same type, because comparing a lifting session with a walk produces a number that
    /// means nothing.
    public func previousOfSameType(in sessions: [CompletedSession]) -> CompletedSession? {
        sessions
            .filter { $0.activityType == activityType && $0.start < start && $0.id != id }
            .max { $0.start < $1.start }
    }
}
