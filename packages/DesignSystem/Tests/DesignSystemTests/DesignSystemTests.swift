import Foundation
import Testing

@testable import DesignSystem

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(DesignSystemModule.schemaVersion == 1)
}

// MARK: - §1.3, the label rule

@Test(
    "a noun of at most two words is a label",
    arguments: ["Protein", "Resting HR", "7-day", "Consistency"]
)
func compliantLabels(label: String) {
    #expect(LabelRule.isCompliant(label))
}

@Test(
    "a sentence is not a label",
    arguments: [
        "Track your protein",
        "Protein. Your daily total",
        "Here's your readiness",
        "Protein intake today",
        "",
        "   "
    ]
)
func bannedLabels(label: String) {
    #expect(!LabelRule.isCompliant(label))
}

@Test("a two-word label that runs long is prose in disguise")
func longLabelsAreRejected() {
    #expect(!LabelRule.isCompliant("Cardiovascular Responsiveness"))
}

// MARK: - §6.2, intensity

@Test("every win scores a point")
func intensityCountsEveryWin() {
    let perfect = DayWins(session: .asPlanned, proteinGrams: 152, steps: 11_240, sleepHours: 7.8)
    #expect(perfect.intensity() == 4)
}

@Test("a planned rest day honoured scores as a session")
func restCountsAsASession() {
    let rested = DayWins(session: .rest, proteinGrams: 100, steps: 2_000, sleepHours: 5)
    #expect(rested.intensity() == 1)
}

@Test("nothing met scores nothing")
func nothingMetScoresZero() {
    let blank = DayWins(session: .missed, proteinGrams: 139, steps: 9_999, sleepHours: 7.49)
    #expect(blank.intensity() == 0)
}

@Test("each threshold is met exactly at its boundary")
func thresholdsAreInclusive() {
    let onTheLine = DayWins(session: .missed, proteinGrams: 140, steps: 10_000, sleepHours: 7.5)
    #expect(onTheLine.intensity() == 3)
}

@Test("thresholds are injectable, so Core can own the real ones later")
func thresholdsAreInjectable() {
    let day = DayWins(session: .missed, proteinGrams: 120, steps: 8_000, sleepHours: 7)
    let relaxed = ConsistencyThresholds(proteinGrams: 120, steps: 8_000, sleepHours: 7)
    #expect(day.intensity(against: .standard) == 0)
    #expect(day.intensity(against: relaxed) == 3)
}

// MARK: - §6.1, the 7 × 17 layout

private let gregorian: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    calendar.firstWeekday = 2
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    gregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
}

@Test("the grid is always 17 columns of 7 rows")
func layoutIsSevenBySeventeen() {
    let slots = ConsistencyLayout.slots(for: [], endingOn: date(2026, 11, 3), calendar: gregorian)
    #expect(slots.count == 17)
    #expect(slots.allSatisfy { $0.count == 7 })
}

@Test("the window ends on the given day and nothing after it is a slot")
func futureSlotsAreEmpty() {
    let end = date(2026, 11, 3)
    let slots = ConsistencyLayout.slots(for: [], endingOn: end, calendar: gregorian)
    let dates = slots.flatMap { $0 }.compactMap { $0?.date }
    #expect(dates.allSatisfy { $0 <= end })
    #expect(dates.contains(end))
    // 3 November 2026 is a Tuesday, so the last column holds Monday and Tuesday only.
    let lastColumn = slots[16].compactMap { $0 }
    #expect(lastColumn.count == 2)
}

@Test("the window is 17 weeks back from the start of the current week")
func windowStartsSeventeenWeeksBack() {
    let slots = ConsistencyLayout.slots(for: [], endingOn: date(2026, 11, 3), calendar: gregorian)
    #expect(slots[0].first??.date == date(2026, 7, 13))
}

@Test("a day with data is matched to its slot whatever time of day it carries")
func suppliedDaysLandInTheRightSlot() {
    let stamped = gregorian.date(byAdding: .hour, value: 19, to: date(2026, 10, 30)) ?? .distantPast
    let wins = DayWins(session: .asPlanned, proteinGrams: 150, steps: 12_000, sleepHours: 8)
    let slots = ConsistencyLayout.slots(
        for: [ConsistencyDay(date: stamped, wins: wins)],
        endingOn: date(2026, 11, 3),
        calendar: gregorian
    )
    let matched = slots.flatMap { $0 }.compactMap { $0 }.filter { $0.wins != nil }
    #expect(matched.count == 1)
    #expect(matched.first?.wins?.intensity() == 4)
}

@Test("days outside the window are dropped rather than wrapped in")
func daysOutsideTheWindowAreDropped() {
    let old = ConsistencyDay(
        date: date(2026, 1, 1),
        wins: DayWins(session: .asPlanned, proteinGrams: 150, steps: 12_000, sleepHours: 8)
    )
    let slots = ConsistencyLayout.slots(for: [old], endingOn: date(2026, 11, 3), calendar: gregorian)
    #expect(slots.flatMap { $0 }.compactMap { $0 }.allSatisfy { $0.wins == nil })
}

// MARK: - §3.2 and §3.4, how a duration reads

@Test(
    "sleep reads as hours and minutes, never as a decimal",
    arguments: [(7.7, "7h42"), (7.5, "7h30"), (6.0, "6h00"), (8.016, "8h01")]
)
func sleepFormatsAsHoursAndMinutes(hours: Double, expected: String) {
    #expect(ConsistencyGrid.sleepText(hours) == expected)
}

@Test("sixty minutes rounds up into the hour rather than reading 7h60")
func sleepRoundsIntoTheNextHour() {
    #expect(ConsistencyGrid.sleepText(7.999) == "8h00")
}
