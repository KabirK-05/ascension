import AscensionCore
import Foundation

/// The one-line summary at the top of Today (spec §F1).
///
/// Rule-based in v1; Foundation Models arrives in a later ticket and will replace the
/// wording, not the contract. Every clause is a fact with a unit and the line carries no
/// encouragement, no second person and no description of the UI beneath it
/// (`docs/DESIGN_RULES.md` §1.2) — "Slept 7h42. Quads sore. Upper A today — protein is
/// 40 g behind pace."
///
/// A clause that would carry no information is dropped rather than padded: no sleep data
/// means no sleep clause, and protein within pace means no protein clause.
enum SummaryLine {

    static func text(for snapshot: TodaySnapshot, verdict: VerdictDisplay) -> String {
        var clauses: [String] = []
        if let sleep = sleepClause(snapshot) { clauses.append(sleep) }
        if let soreness = sorenessClause(snapshot) { clauses.append(soreness) }
        clauses.append(sessionClause(snapshot, verdict: verdict))
        return clauses.map { "\($0)." }.joined(separator: " ")
    }

    private static func sleepClause(_ snapshot: TodaySnapshot) -> String? {
        guard let minutes = snapshot.today.sleep.asleepMinutes else { return nil }
        return "Slept \(TodayFormat.duration(minutes: minutes))"
    }

    /// Only the groups actually marked sore. "Nothing is sore" is not news, and the
    /// verdict already carries it.
    private static func sorenessClause(_ snapshot: TodaySnapshot) -> String? {
        guard let soreness = snapshot.today.checkIn?.soreness else { return nil }
        let sore = MuscleGroup.allCases
            .filter { soreness.level(for: $0) == .sore }
            .map(\.rawValue)
        guard !sore.isEmpty else { return nil }
        return "\(list(sore).capitalizedFirst) sore"
    }

    /// The session, with the protein gap hung off it the way the spec's own example
    /// does, so the line stays one sentence rather than becoming a list.
    private static func sessionClause(_ snapshot: TodaySnapshot,
                                      verdict: VerdictDisplay) -> String {
        var clause = verdictClause(snapshot, verdict: verdict)
        if let behind = ProteinPace.gramsBehind(consumed: snapshot.today.nutrition.proteinG,
                                                target: snapshot.goals.targets.proteinG,
                                                at: snapshot.clock.now) {
            clause += " — protein is \(Int(behind.rounded())) g behind pace"
        }
        return clause
    }

    private static func verdictClause(_ snapshot: TodaySnapshot,
                                      verdict: VerdictDisplay) -> String {
        let planned = snapshot.plannedSession.map { SessionName.of($0, in: snapshot.program) }
        switch verdict {
        case .rest:
            return "Rest day"
        case .trainAsPlanned:
            return planned.map { "\($0) today" } ?? "Train as planned"
        case .capIntensity:
            return planned.map { "\($0) today, capped" } ?? "Cap intensity"
        case .swap(let kind):
            return "Swap to \(SessionName.of(kind, in: snapshot.program))"
        case .activeRecovery:
            return "Active recovery today"
        }
    }

    /// `"quads"`, `"quads and glutes"`, `"quads, glutes and core"`.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default:
            return items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }
}

extension String {
    /// Sentence case without touching the rest of the string, so "HRV" stays "HRV".
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
