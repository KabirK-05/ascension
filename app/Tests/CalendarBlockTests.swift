import AscensionCore
import Foundation
import Testing

@testable import Ascension

/// Which calendar events become training blocks.
///
/// This is the rule that decides, on a day with two eligible workouts, which one the week
/// is judged on — so handing the matcher a lunch meeting would silently credit the wrong
/// session (ASC-20 flagged exactly this gap).
@Suite("training blocks")
struct CalendarBlockTests {
    private let titles = TrainingBlockFilter.titles(in: Seed.program)

    @Test("a block named for a session in the program counts")
    func programSessionTitle() {
        let name = Seed.program.sessions.values.first?.name ?? "Lower A"
        #expect(TrainingBlockFilter.isBlock(title: name, isAllDay: false, titles: titles))
    }

    @Test("the training vocabulary counts, with the event's own wording around it")
    func vocabulary() {
        #expect(TrainingBlockFilter.isBlock(title: "Gym", isAllDay: false, titles: titles))
        #expect(TrainingBlockFilter.isBlock(title: "Evening lift with Sam",
                                            isAllDay: false, titles: titles))
    }

    @Test("case and accents do not decide whether a block is a block")
    func caseInsensitive() {
        #expect(TrainingBlockFilter.isBlock(title: "GYM", isAllDay: false, titles: titles))
        #expect(TrainingBlockFilter.isBlock(title: "  gym  ", isAllDay: false, titles: titles))
    }

    @Test("an ordinary meeting is not a training block")
    func ordinaryEvent() {
        #expect(!TrainingBlockFilter.isBlock(title: "Lunch with Priya",
                                             isAllDay: false, titles: titles))
        #expect(!TrainingBlockFilter.isBlock(title: "1:1", isAllDay: false, titles: titles))
    }

    @Test("an all-day event is never a block, however it is named")
    func allDayNeverCounts() {
        #expect(!TrainingBlockFilter.isBlock(title: "Gym", isAllDay: true, titles: titles))
    }

    @Test("an untitled event is not a block")
    func untitled() {
        #expect(!TrainingBlockFilter.isBlock(title: "", isAllDay: false, titles: titles))
        #expect(!TrainingBlockFilter.isBlock(title: "   ", isAllDay: false, titles: titles))
    }
}
