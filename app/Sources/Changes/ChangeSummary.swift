import AscensionCore
import Foundation
import SyncClient

/// Turns a write into one line a person reads at a glance.
///
/// Pure, and tested, because this is the only text in Settings → Changes and
/// `docs/DESIGN_RULES.md` §1 leaves no room for a second line explaining the first. A
/// summary that cannot say what changed says the kind and stops, rather than inventing
/// detail.
///
/// The shape is `Noun old → new`, grouped by ` · ` when one write changed several fields,
/// which is the same separator the daily log uses.
enum ChangeSummary {

    static func targets(from old: GoalTargets, to new: GoalTargets) -> String {
        var parts: [String] = []
        append(&parts, "Calories", old.kcal, new.kcal)
        append(&parts, "Protein", old.proteinG, new.proteinG, unit: " g")
        append(&parts, "Protein floor", old.proteinMinG, new.proteinMinG, unit: " g")
        append(&parts, "Fat floor", old.fatMinG, new.fatMinG, unit: " g")
        append(&parts, "Fat ceiling", old.fatMaxG, new.fatMaxG, unit: " g")
        append(&parts, "Steps", old.steps, new.steps)
        append(&parts, "Sleep", old.sleepMinutes, new.sleepMinutes, unit: " min")
        return parts.isEmpty ? "Targets unchanged" : parts.joined(separator: " · ")
    }

    static func program(from old: ProgramDocument, to new: ProgramDocument) -> String {
        old.name == new.name ? "Program edited" : "Program \(old.name) → \(new.name)"
    }

    static func flag(key: String, value: JSONValue) -> String {
        let name = flagNames[key] ?? key
        switch value {
        case .bool(let on): return "\(name) \(on ? "on" : "off")"
        case .string(let text): return "\(name) \(text)"
        default: return "\(name) changed"
        }
    }

    static func staples(_ count: Int) -> String {
        "Staples — \(count)"
    }

    static func meal(_ payload: MutationPayload.LoggedMealPayload) -> String {
        let totals = payload.totals
        return "\(payload.meal.rawValue.capitalized) "
            + "\(number(Int(totals.kcal.rounded()))) kcal · "
            + "\(number(Int(totals.proteinG.rounded()))) g protein"
    }

    static func water(millilitres: Double) -> String {
        "Water \(number(Int(millilitres.rounded()))) ml"
    }

    static func topSet(_ payload: MutationPayload.TopSetPayload, name: String) -> String {
        "\(name) \(payload.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg"
            + " × \(payload.reps)"
    }

    static func checkIn(energy: Int) -> String {
        "Check-in — energy \(energy)"
    }

    static func scheduledWorkout(kind: SessionKind, on date: CalendarDate) -> String {
        "\(kind.rawValue) sent to Watch · \(day(date))"
    }

    static let export = "Export written"
    static let suggestion = "Suggestion accepted"

    /// `Nov 5`, which is how a row dates itself without a second line.
    static func day(_ date: CalendarDate) -> String {
        guard let instant = Timestamp(rawValue: "\(date.rawValue)T12:00:00Z")?.date else {
            return date.rawValue
        }
        return instant.formatted(.dateTime.month(.abbreviated).day().timeZone())
    }

    private static func append(_ parts: inout [String], _ noun: String,
                               _ old: Int, _ new: Int, unit: String = "") {
        guard old != new else { return }
        parts.append("\(noun) \(number(old))\(unit) → \(number(new))\(unit)")
    }

    private static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static let flagNames = [
        "remoteBridgeEnabled": "Remote bridge",
        "museWritesEnabled": "Muse writes",
        "museWriteMode": "Muse write mode",
        "rawDetailSyncEnabled": "Raw detail sync",
        "foundationModelsEnabled": "On-device model"
    ]
}
