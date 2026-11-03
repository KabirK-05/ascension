import AscensionCore
import DesignSystem
import Foundation

/// What today's verdict says on screen.
///
/// Separate from ``ReadinessVerdict`` on purpose. The engine answers *how hard may the
/// prescribed session be run*, and on a rest day nothing is prescribed, so it correctly
/// answers `trainAsPlanned` — which, rendered literally, would tell the user to train on
/// a Sunday. The rest day is a presentation case and it is handled here, rather than by
/// changing an engine that is already merged and tested.
public enum VerdictDisplay: Hashable, Sendable {
    case rest
    case trainAsPlanned
    case capIntensity
    case swap(SessionKind)
    case activeRecovery

    /// The verdict shown beside the score. This is a value, not a label — it is the
    /// answer the screen exists to give, and nothing explains it underneath.
    public var text: String {
        switch self {
        case .rest: return "Rest day"
        case .trainAsPlanned: return "Train as planned"
        case .capIntensity: return "Cap intensity"
        case .swap(let kind): return "Swap to \(SessionName.of(kind))"
        case .activeRecovery: return "Active recovery"
        }
    }

    /// Today's verdict, given what the engine said and what the program prescribes.
    public static func of(_ verdict: ReadinessVerdict,
                          plannedSession: SessionKind?,
                          suggestedSession: SessionKind?) -> VerdictDisplay {
        guard let plannedSession, plannedSession.isTrainingDay else { return .rest }
        switch verdict {
        case .trainAsPlanned: return .trainAsPlanned
        case .capIntensity: return .capIntensity
        case .activeRecovery: return .activeRecovery
        case .swapSession:
            // The engine only ever emits `swapSession` alongside a session to swap to,
            // but the type allows the pair to disagree. Falling back to the honest
            // verdict beats rendering "Swap to" with nothing after it.
            guard let suggestedSession else { return .activeRecovery }
            return .swap(suggestedSession)
        }
    }

    /// The session to put in front of the user, so the session card can never
    /// contradict the verdict above it. `nil` means nothing is prescribed today.
    public func prescribedSession(planned: SessionKind?) -> SessionKind? {
        switch self {
        case .rest, .activeRecovery: return nil
        case .swap(let kind): return kind
        case .trainAsPlanned, .capIntensity: return planned
        }
    }
}

/// The name a session goes by on screen.
public enum SessionName {
    /// The program's own name, falling back to a readable form of the kind when the
    /// program carries no template for it.
    public static func of(_ kind: SessionKind, in program: ProgramDocument? = nil) -> String {
        if let name = program?.sessions[kind]?.name, !name.isEmpty { return name }
        switch kind {
        case .upperA: return "Upper A"
        case .upperB: return "Upper B"
        case .lowerA: return "Lower A"
        case .lowerB: return "Lower B"
        case .fullBody: return "Full body"
        case .zone2: return "Zone 2"
        case .rest: return "Rest"
        }
    }
}

/// The session to do today. Absent from the presentation entirely on a rest day or a
/// stand-down, because a card that says nothing does not ship (§2.1).
public struct SessionPlan: Hashable, Sendable {
    public let kind: SessionKind
    public let name: String
    public let exercises: Int
}

/// The readiness hero.
public struct ReadinessPanel: Hashable, Sendable {
    public let score: Int
    public let verdict: VerdictDisplay
    /// The engine's top two facts, verbatim. Facts with units, never advice (spec §F5).
    public let reasons: [String]
}

/// Calories and protein against their targets.
public struct NutritionPanel: Hashable, Sendable {
    public let kcal: Double
    public let kcalTarget: Double
    public let proteinGrams: Double
    public let proteinTargetGrams: Double
}

/// One row of the day's measurements.
public struct MeasurementRow: Hashable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let unit: String?
    public let spokenValue: String?
    public let progress: Double?

    public var id: String { label }

    public init(label: String, value: String, unit: String? = nil,
                spokenValue: String? = nil, progress: Double? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.spokenValue = spokenValue
        self.progress = progress
    }
}

/// The 17-week grid, the thresholds its cells were scored against, and the calendar it
/// is laid out in.
public struct ConsistencyPanel: Hashable, Sendable {
    public let days: [ConsistencyDay]
    public let thresholds: ConsistencyThresholds
    public let endDate: Date
    public let calendar: Calendar
}

/// Everything on the screen, derived once from a ``TodaySnapshot``.
public struct TodayPresentation: Hashable, Sendable {
    /// The day being shown, for the navigation bar. The tab is already called Today, so
    /// the bar carries the date instead of repeating the word (§2.1).
    public let date: Date

    /// The one-line rule-based summary (spec §F1). Facts, never encouragement.
    public let summary: String
    public let readiness: ReadinessPanel
    /// `nil` on a rest day or a stand-down.
    public let session: SessionPlan?
    public let nutrition: NutritionPanel
    public let measurements: [MeasurementRow]
    public let consistency: ConsistencyPanel
}
