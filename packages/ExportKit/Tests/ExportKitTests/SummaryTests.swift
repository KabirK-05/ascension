import AscensionCore
import Foundation
import Testing

@testable import ExportKit

@Suite("summary-latest.md stays short and tells the truth")
struct SummaryTests {
    private func renderer(_ snapshot: ExportSnapshot) -> SummaryRenderer {
        SummaryRenderer(environment: Fixture.environment, snapshot: snapshot)
    }

    @Test("a realistic 28 days stays under the 150-line limit")
    func monthStaysUnderTheLimit() throws {
        let text = try renderer(Fixture.monthSnapshot).render()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count

        #expect(lines < SummaryRenderer.lineLimit)
        #expect(SummaryRenderer.lineLimit == 150)
    }

    @Test("the limit holds with every optional line populated")
    func limitHoldsAtWorstCase() throws {
        // Four open suggestions and a deload week — every line the summary can emit.
        var snapshot = Fixture.monthSnapshot
        snapshot.documents.program.deload = DeloadSettings(active: true, loadFactor: 0.6,
                                                           volumeFactor: 0.5)
        snapshot.suggestions = (1...4).map { index in
            OpenSuggestion(id: "sug_0\(index)",
                           createdAt: Fixture.exportedAt,
                           kind: "calorieAdjustment",
                           text: "A suggestion long enough to wrap a terminal line "
                               + "but still only one line of markdown.")
        }
        let lines = try renderer(snapshot).render()
            .split(separator: "\n", omittingEmptySubsequences: false).count

        #expect(lines < SummaryRenderer.lineLimit)
    }

    @Test("the whole summary matches its golden file")
    func matchesGolden() throws {
        try Golden.expect(try renderer(Fixture.monthSnapshot).render(),
                          matches: "summary-latest.expected.md")
    }

    @Test("a summary over the limit fails loudly instead of truncating")
    func overTheLimitThrows() throws {
        var snapshot = Fixture.monthSnapshot
        snapshot.suggestions = (1...200).map { index in
            OpenSuggestion(id: String(format: "sug_%03d", index),
                           createdAt: Fixture.exportedAt,
                           kind: "calorieAdjustment", text: "noise")
        }

        #expect(throws: ExportError.self) {
            _ = try self.renderer(snapshot).render()
        }
    }

    @Test("the last-14-days table has a row per day and a stable header")
    func recentTableShape() throws {
        let text = try renderer(Fixture.monthSnapshot).render()
        let rows = text.split(separator: "\n").filter { $0.hasPrefix("| 2026-") }

        #expect(rows.count == SummaryWindow.tableDays)
        #expect(text.contains("| Date | Day | Readiness | Session | kcal | Protein g "
            + "| Steps | Sleep | Weight kg | Wins |"))
    }

    @Test("targets are read from the document, never hardcoded")
    func targetsComeFromTheDocument() throws {
        var snapshot = Fixture.monthSnapshot
        snapshot.documents.goalSettings.targets.kcal = 2_050
        snapshot.documents.goalSettings.targets.proteinG = 160
        let text = try renderer(snapshot).render()

        #expect(text.contains("- Calories: 2,050 kcal"))
        #expect(text.contains("- Protein: 160 g (floor 140 g)"))
    }

    @Test("adherence counts the stored wins, so it cannot disagree with the grid")
    func adherenceUsesStoredWins() throws {
        let snapshot = Fixture.monthSnapshot
        let window = SummaryWindow(rollups: snapshot.rollups)
        let text = try renderer(snapshot).render()

        #expect(text.contains("- Protein ≥ 140 g: "
            + SummaryWindow.ratio(window.winDays(\.protein), of: 28)))
        #expect(text.contains("- Steps ≥ 10,000: "
            + SummaryWindow.ratio(window.winDays(\.steps), of: 28)))
        #expect(window.sessionsPlanned == 16)
        #expect(window.sessionsDone == 13)
    }

    @Test("averages skip unmeasured days rather than averaging in a zero")
    func averagesSkipNulls() {
        let snapshot = Fixture.monthSnapshot
        let window = SummaryWindow(rollups: snapshot.rollups)
        let logged = snapshot.rollups.compactMap { $0.nutrition.kcal }

        #expect(logged.count == 27)
        let mean = logged.reduce(0, +) / Double(logged.count)
        #expect(window.meanKcal == mean)
        #expect((window.meanKcal ?? 0) > 2_000)
    }

    @Test("an empty window renders rather than crashing")
    func emptyWindowRenders() throws {
        let snapshot = ExportSnapshot(rollups: [], documents: Fixture.documents)
        let text = try renderer(snapshot).render()

        #expect(text.contains("Window no data · 0 days"))
        #expect(text.contains("| Calories kcal | — | — |"))
        #expect(text.contains("- none"))
    }
}
