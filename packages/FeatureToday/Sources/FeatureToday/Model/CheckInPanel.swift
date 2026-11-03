import AscensionCore
import Foundation

/// One muscle group's tap target in the check-in.
public struct CheckInGroupState: Hashable, Sendable, Identifiable {
    public let group: MuscleGroup
    /// A noun, one word (`docs/DESIGN_RULES.md` §1.3).
    public let label: String
    public let level: SorenessLevel

    public var id: MuscleGroup { group }

    public init(group: MuscleGroup, level: SorenessLevel) {
        self.group = group
        self.label = group.rawValue.capitalizedFirst
        self.level = level
    }

    /// What VoiceOver reads as this control's value. The state is never carried by
    /// colour alone.
    public var spokenLevel: String {
        switch level {
        case .none: return "Not sore"
        case .mild: return "Mild"
        case .sore: return "Sore"
        }
    }
}

/// The morning check-in, as the screen draws it (spec §F4).
///
/// Present only while today has no check-in. Once one is in, this is `nil` and the
/// controls are gone for the day — a completed check-in is not a card that stays.
public struct CheckInPanel: Hashable, Sendable {
    public let groups: [CheckInGroupState]
    /// The closed 1–5 scale, from the contract rather than from a literal.
    public let energyScale: [Int]
    /// The energy last tapped, so a save in flight and a failed one show what they are
    /// about. `nil` until something is tapped.
    public let energy: Int?
    public let status: CheckInStatus

    public init(groups: [CheckInGroupState], energy: Int?, status: CheckInStatus) {
        self.groups = groups
        self.energyScale = Array(CheckInRollup.energyRange)
        self.energy = energy
        self.status = status
    }

    /// Built from a draft, in the contract's own group order.
    public static func of(_ state: CheckInState) -> CheckInPanel {
        CheckInPanel(groups: MuscleGroup.allCases.map {
            CheckInGroupState(group: $0, level: state.draft.level(for: $0))
        },
        energy: state.energy,
        status: state.status)
    }

    /// The groups the user has actually marked, for VoiceOver's summary of the set.
    public var marked: [CheckInGroupState] {
        groups.filter { $0.level != .none }
    }
}
