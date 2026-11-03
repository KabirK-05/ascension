import AscensionCore
import Foundation

/// `summary-latest.md` — the rolling 28-day summary, overwritten every export.
///
/// This is the file an AI reads first, so the 150-line limit (spec §9.1) is a hard
/// requirement rather than a style note: past it, a reader starts spending its budget
/// on the summary instead of the question. `render()` enforces it.
struct SummaryRenderer {
    static let fileName = "summary-latest.md"
    static let lineLimit = 150

    let environment: ExportEnvironment
    let snapshot: ExportSnapshot

    private var window: SummaryWindow { SummaryWindow(rollups: snapshot.rollups) }
    private var settings: GoalSettingsDocument { snapshot.documents.goalSettings }

    /// The whole file, or `summaryTooLong` if it would exceed the limit. Failing loudly
    /// is deliberate: a silently truncated summary would be read as complete.
    func render() throws -> String {
        let text = compose()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        guard lines <= Self.lineLimit else {
            throw ExportError.summaryTooLong(lines: lines, limit: Self.lineLimit)
        }
        return text
    }

    private func compose() -> String {
        var sections = [preamble(), targets(), program()]
        sections.append(averages())
        sections.append(adherence())
        sections.append(recentTable())
        sections.append(suggestions())
        return sections.joined(separator: "\n") + "\n"
    }

    private func preamble() -> String {
        let window = self.window
        let span = [window.firstDate?.rawValue, window.lastDate?.rawValue]
            .compactMap { $0 }
        let range = span.count == 2 ? "\(span[0]) → \(span[1])" : "no data"
        return """
        # Ascension — summary

        Generated \(environment.exportedAt.rawValue) · schemaVersion \
        \(ExportKitModule.schemaVersion)
        Window \(range) · \(window.dayCount) days · \(settings.timezone)

        """
    }

    private func targets() -> String {
        let targets = settings.targets
        return """
        ## Targets

        - Calories: \(Format.grouped(targets.kcal)) kcal
        - Protein: \(targets.proteinG) g (floor \(targets.proteinMinG) g)
        - Fat: \(targets.fatMinG)–\(targets.fatMaxG) g
        - Steps: \(Format.grouped(targets.steps))
        - Sleep: \(Format.duration(minutes: targets.sleepMinutes))
        - Goal weight: \(Format.decimal(settings.body.goalWeightKg, places: 1)) kg

        """
    }

    private func program() -> String {
        let document = snapshot.documents.program
        let week = (1...ProgramDocument.weekdayCount).compactMap { weekday -> String? in
            guard let kind = document.kind(forWeekday: weekday),
                  let name = Format.weekdayName(isoWeekday: weekday) else { return nil }
            return "\(name) \(kind.rawValue)"
        }
        let deload = document.deload.active ? " · deload week" : ""
        return """
        ## Program

        - \(document.name)\(deload)
        - Week: \(week.joined(separator: " · "))

        """
    }

    private func suggestions() -> String {
        let open = snapshot.suggestions
        let lines = open.isEmpty
            ? ["- none"]
            : open.map { "- \($0.kind): \($0.text) (raised \($0.createdAt.rawValue))" }
        return """
        ## Open suggestions

        \(lines.joined(separator: "\n"))
        """
    }
}

extension Format {
    private static let isoWeekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// ISO-8601 weekday number to name: Monday = 1 (`docs/EXPORT_SCHEMA.md` §2.2).
    static func weekdayName(isoWeekday: Int) -> String? {
        guard isoWeekdayNames.indices.contains(isoWeekday - 1) else { return nil }
        return isoWeekdayNames[isoWeekday - 1]
    }
}
