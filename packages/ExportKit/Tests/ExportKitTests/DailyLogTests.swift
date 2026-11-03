import AscensionCore
import Foundation
import Testing

@testable import ExportKit

@Suite("daily-log.md is append-only and matches the §9.1 shape")
struct DailyLogTests {
    private var renderer: DailyLogRenderer {
        DailyLogRenderer(environment: Fixture.environment,
                         snapshot: Fixture.workedExampleSnapshot)
    }

    @Test("the §9.1 worked example renders line for line")
    func workedExampleMatchesSpec() throws {
        let block = renderer.block(for: Fixture.workedExampleRollup)
        let lines = block.split(separator: "\n").map(String.init)

        #expect(lines[0] == "## 2026-11-09 (Mon)")
        #expect(lines[1] == "- Readiness: 82 — train as planned "
            + "(slept 7h42; HRV near baseline)")
        #expect(lines[2] == "- Workout (Apple Workout): Strength, 19:04–19:55, 51 min, "
            + "368 kcal, HR 120 avg / 150 max")
        #expect(lines[3] == "- Top sets: goblet squat 24 kg × 12 · DB bench 20 kg × 11 "
            + "· RDL 22 kg × 12")
        #expect(lines[4] == "- Food: 2,180 kcal · protein 148 g / 150 g · fat 64 g "
            + "· carbs 248 g")
        #expect(lines[5] == "  - Lunch: chicken breast 200 g + rice 150 g — 650 kcal, "
            + "55 g protein")
        #expect(lines[6] == "- Sleep (last night): 7h42, resting HR 58, HRV 41 ms")
        #expect(lines[7] == "- Weight: 73.6 kg (7-day avg 73.9, −0.4 kg/week) "
            + "· Steps: 10,240")
        #expect(lines.count == 8)
    }

    @Test("an unmeasured line is omitted rather than written blank")
    func unmeasuredLinesAreOmitted() {
        let rollup = DayRollup(date: CalendarDate.literal("2026-11-10"),
                               timezone: Seed.timezone,
                               updatedAt: Timestamp.literal("2026-11-10T23:00:00-05:00"),
                               training: TrainingRollup(sessionPlanned: .lowerA),
                               wins: Wins(session: false, protein: false,
                                          steps: false, sleep: false))
        let block = renderer.block(for: rollup)

        #expect(block == "## 2026-11-10 (Tue)\n- Workout: none (lowerA planned)\n")
    }

    @Test("a planned rest day with no workout says so")
    func restDayIsNamed() {
        let rollup = DayRollup(date: CalendarDate.literal("2026-11-11"),
                               timezone: Seed.timezone,
                               updatedAt: Timestamp.literal("2026-11-11T23:00:00-05:00"),
                               training: TrainingRollup(sessionPlanned: .rest),
                               wins: Wins(session: true, protein: false,
                                          steps: false, sleep: false))

        #expect(renderer.block(for: rollup).contains("- Workout: none (rest day)"))
    }

    @Test("the full month journal matches its golden file")
    func monthJournalMatchesGolden() throws {
        let snapshot = Fixture.monthSnapshot
        let appender = DailyLogAppender(
            renderer: DailyLogRenderer(environment: Fixture.environment,
                                       snapshot: snapshot))
        let append = appender.append(snapshot.rollups, to: nil)
        let contents = try #require(append.contents)

        #expect(append.addedDates.count == 28)
        try Golden.expect(contents, matches: "daily-log.expected.md")
    }

    @Test("appending twice over overlapping ranges duplicates no day")
    func overlappingAppendsDoNotDuplicate() throws {
        let snapshot = Fixture.monthSnapshot
        let appender = DailyLogAppender(
            renderer: DailyLogRenderer(environment: Fixture.environment,
                                       snapshot: snapshot))

        let firstPass = appender.append(Array(snapshot.rollups.prefix(20)), to: nil)
        let afterFirst = try #require(firstPass.contents)
        // The second export's range starts 6 days inside the first one's.
        let secondPass = appender.append(Array(snapshot.rollups.suffix(14)),
                                         to: afterFirst)
        let afterSecond = try #require(secondPass.contents)

        #expect(firstPass.addedDates.count == 20)
        #expect(secondPass.addedDates.count == 8)
        let headers = DailyLogAppender.datesPresent(in: afterSecond)
        #expect(headers.count == 28)
        for date in snapshot.rollups.map(\.date.rawValue) {
            let occurrences = afterSecond.components(separatedBy: "## \(date)").count - 1
            #expect(occurrences == 1, "\(date) appears \(occurrences) times")
        }
    }

    @Test("a third export of days already written changes nothing")
    func reexportIsANoOp() throws {
        let snapshot = Fixture.monthSnapshot
        let appender = DailyLogAppender(
            renderer: DailyLogRenderer(environment: Fixture.environment,
                                       snapshot: snapshot))
        let written = try #require(appender.append(snapshot.rollups, to: nil).contents)
        let again = appender.append(snapshot.rollups, to: written)

        #expect(again.contents == nil)
        #expect(again.addedDates.isEmpty)
    }

    @Test("a day already in the file is never rewritten, even if its data changed")
    func existingDaysAreNotRewritten() throws {
        let appender = DailyLogAppender(renderer: renderer)
        let hand = "# Ascension — daily log\n\n## 2026-11-09 (Mon)\n- a note I wrote\n"
        let append = appender.append([Fixture.workedExampleRollup], to: hand)

        #expect(append.contents == nil)
        #expect(hand.contains("- a note I wrote"))
    }

    @Test("header dates are read back from a hand-edited journal")
    func headersParseFromArbitraryText() {
        let text = """
        # Ascension — daily log

        ## 2026-11-03 (Tue)
        - Readiness: 70 — cap intensity

        ## not-a-date
        ## 2026-11-04 (Wed)
        some prose about 2026-11-05 that is not a header
        """

        #expect(DailyLogAppender.datesPresent(in: text) == ["2026-11-03", "2026-11-04"])
    }
}
