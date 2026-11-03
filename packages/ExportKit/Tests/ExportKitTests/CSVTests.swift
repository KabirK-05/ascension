import AscensionCore
import Foundation
import Testing

@testable import ExportKit

@Suite("CSV escaping and column order")
struct CSVTests {
    @Test("a value holding a comma is quoted")
    func commasAreQuoted() throws {
        let table = CSVTable(name: "t", columns: ["name"],
                             rows: [[.text("chicken, rice and veg")]])
        let text = try render(table)

        #expect(text == "name\n\"chicken, rice and veg\"\n")
    }

    @Test("a double quote is doubled inside a quoted field")
    func quotesAreDoubled() throws {
        let table = CSVTable(name: "t", columns: ["note"],
                             rows: [[.text("he said \"light\" today")]])
        let text = try render(table)

        #expect(text == "note\n\"he said \"\"light\"\" today\"\n")
    }

    @Test("a newline inside a value stays inside one quoted field")
    func newlinesAreQuoted() throws {
        let table = CSVTable(name: "t", columns: ["note"],
                             rows: [[.text("first line\nsecond line")]])
        let text = try render(table)

        #expect(text == "note\n\"first line\nsecond line\"\n")
        // Quoted, so the record is still one row to any RFC 4180 reader.
        #expect(text.split(separator: "\n").count == 3)
    }

    @Test("a carriage return is quoted too")
    func carriageReturnsAreQuoted() throws {
        let table = CSVTable(name: "t", columns: ["note"], rows: [[.text("a\r\nb")]])

        #expect(try render(table) == "note\n\"a\r\nb\"\n")
    }

    @Test("null is an empty field and an empty string is a quoted empty")
    func nullIsNotEmptyString() throws {
        let table = CSVTable(name: "t", columns: ["measured", "note"],
                             rows: [[.null, .text("")], [.number(41), .text("ok")]])
        let text = try render(table)

        #expect(text == "measured,note\n,\"\"\n41,ok\n")
    }

    @Test("leading and trailing spaces survive, because they are quoted")
    func surroundingSpacesAreQuoted() throws {
        let table = CSVTable(name: "t", columns: ["name"], rows: [[.text(" rice ")]])

        #expect(try render(table) == "name\n\" rice \"\n")
    }

    @Test("numbers carry no locale and integral doubles lose their .0")
    func numbersAreLocaleFree() throws {
        let table = CSVTable(name: "t", columns: ["a", "b", "c", "d"],
                             rows: [[.number(24), .number(73.6), .number(-0.4),
                                     .integer(10_240)]])

        #expect(try render(table) == "a,b,c,d\n24,73.6,-0.4,10240\n")
    }

    @Test("a row that does not match its header fails loudly")
    func rowWidthIsChecked() {
        let table = CSVTable(name: "weight", columns: ["date", "weightKg"],
                             rows: [[.text("2026-11-09")]])

        #expect(throws: ExportError.csvRowWidthMismatch(table: "weight", row: 0,
                                                        expected: 2, found: 1)) {
            _ = try table.encoded()
        }
    }

    @Test("every table's header repeats the JSON field names")
    func headersMatchJSONFieldNames() {
        let tables = CSVTables.all(for: Fixture.monthSnapshot)
        let byName = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0) })

        #expect(tables.map(\.name) == ["rollups", "meals", "topSets", "checkIns",
                                       "readiness", "workouts", "sleep", "weight"])
        #expect(byName["meals"]?.columns == ["date", "meal", "foodItemId", "name",
                                             "grams", "kcal", "proteinG", "fatG",
                                             "carbsG"])
        #expect(byName["topSets"]?.columns == ["date", "exerciseId", "weightKg", "reps"])
        #expect(byName["sleep"]?.columns == ["date", "asleepMinutes", "inBedMinutes",
                                             "consistencySd7Minutes"])
        #expect(byName["weight"]?.columns == ["date", "weightKg", "weightAvg7Kg",
                                              "rateKgPerWeek", "bodyFatPct", "waistCm"])
    }

    @Test("the column order is the same on every run")
    func columnOrderIsStable() throws {
        let first = try CSVTables.all(for: Fixture.monthSnapshot).map(render)
        let second = try CSVTables.all(for: Fixture.monthSnapshot).map(render)

        #expect(first == second)
    }

    @Test("each entity CSV matches its golden file")
    func tablesMatchGoldens() throws {
        for table in CSVTables.all(for: Fixture.monthSnapshot) {
            try Golden.expect(try render(table), matches: "\(table.name).expected.csv")
        }
    }

    @Test("an unmeasured day writes nulls, not zeroes")
    func unmeasuredDayWritesNulls() throws {
        let rollup = DayRollup(date: CalendarDate.literal("2026-11-30"),
                               timezone: Seed.timezone, updatedAt: Fixture.exportedAt,
                               wins: Wins(session: false, protein: false,
                                          steps: false, sleep: false))
        let table = CSVTables.rollups([rollup])
        let text = try render(table)
        let row = try #require(text.split(separator: "\n").last).split(
            separator: ",", omittingEmptySubsequences: false).map(String.init)
        let fields = Dictionary(uniqueKeysWithValues: zip(table.columns, row))

        // Every measurement is empty, never 0 — `null` means *not measured*.
        for column in table.columns where column.hasPrefix("nutrition.")
            || column.hasPrefix("vitals.") || column.hasPrefix("body.")
            || column.hasPrefix("activity.") || column.hasPrefix("sleep.") {
            #expect(fields[column] == "", "\(column) should be empty, was \(fields[column] ?? "?")")
        }
        // Counts and flags are facts about the day, so they do carry a value.
        #expect(fields["training.workoutCount"] == "0")
        #expect(fields["training.sessionDone"] == "false")
        #expect(fields["wins.total"] == "0")
    }

    private func render(_ table: CSVTable) throws -> String {
        try #require(String(data: try table.encoded(), encoding: .utf8))
    }
}
