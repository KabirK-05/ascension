import Foundation
import Testing

@testable import AscensionCore

@Suite("goal settings reject what the contract rejects")
struct GoalSettingsInvariantTests {
    @Test("a fat floor below 60 g is rejected", arguments: [59, 40, 0, -10])
    func fatFloorIsEnforced(_ grams: Int) {
        var document = Seed.goalSettings
        document.targets.fatMinG = grams
        #expect(throws: DomainValidationError.fatFloorBelowMinimum(grams)) {
            try document.validate()
        }
    }

    @Test("a fat floor of exactly 60 g is accepted")
    func fatFloorBoundaryIsAccepted() throws {
        var document = Seed.goalSettings
        document.targets.fatMinG = 60
        try document.validate()
    }

    @Test("an inverted fat range is rejected")
    func invertedFatRangeIsRejected() {
        var document = Seed.goalSettings
        document.targets.fatMinG = 80
        document.targets.fatMaxG = 70
        #expect(throws: DomainValidationError.fatRangeInverted(min: 80, max: 70)) {
            try document.validate()
        }
    }

    @Test("a calorie target outside 1400...4000 is rejected", arguments: [1399, 4001, 0])
    func calorieRangeIsEnforced(_ kcal: Int) {
        var document = Seed.goalSettings
        document.targets.kcal = kcal
        #expect(throws: DomainValidationError.calorieTargetOutOfRange(kcal)) {
            try document.validate()
        }
    }

    @Test("the calorie bounds themselves are accepted", arguments: [1400, 4000])
    func calorieBoundsAreAccepted(_ kcal: Int) throws {
        var document = Seed.goalSettings
        document.targets.kcal = kcal
        try document.validate()
    }

    @Test("a protein floor above the protein target is rejected")
    func proteinFloorIsEnforced() {
        var document = Seed.goalSettings
        document.targets.proteinMinG = 160
        #expect(throws: DomainValidationError.proteinFloorAboveTarget(min: 160, target: 150)) {
            try document.validate()
        }
    }
}

@Suite("a program must describe a legal week")
struct ProgramInvariantTests {
    @Test("a week with fewer or more than 7 days is rejected", arguments: [6, 8])
    func dayCountIsEnforced(_ count: Int) {
        var document = Seed.program
        if count < 7 {
            document.days.removeLast(7 - count)
        } else {
            document.days.append(ProgramDayEntry(weekday: 8, kind: .rest))
        }
        #expect(throws: DomainValidationError.programDayCountWrong(count)) {
            try document.validate()
        }
    }

    @Test("a week that repeats or skips a weekday is rejected")
    func weekdaysMustCoverOneThroughSeven() {
        var document = Seed.program
        document.days[6] = ProgramDayEntry(weekday: 6, kind: .rest)
        #expect(throws: DomainValidationError.programWeekdaysInvalid([1, 2, 3, 4, 5, 6, 6])) {
            try document.validate()
        }
    }

    @Test("a planned session with no template is rejected")
    func plannedSessionsNeedTemplates() {
        var document = Seed.program
        document.sessions[.upperB] = nil
        #expect(throws: DomainValidationError.programSessionMissing(.upperB)) {
            try document.validate()
        }
    }

    @Test("a template no day plans is rejected")
    func templatesMustBePlanned() {
        var document = Seed.program
        document.sessions[.fullBody] = Seed.fullBodySession
        #expect(throws: DomainValidationError.programSessionUnreferenced(.fullBody)) {
            try document.validate()
        }
    }

    @Test("a template with no exercises is rejected")
    func templatesNeedExercises() {
        var document = Seed.program
        document.sessions[.upperA] = SessionTemplateEntry(name: "Upper A", exercises: [])
        #expect(throws: DomainValidationError.programSessionEmpty(.upperA)) {
            try document.validate()
        }
    }

    @Test("training the same region on back-to-back days is rejected")
    func sameRegionNeeds48Hours() {
        var document = Seed.program
        document.days[2] = ProgramDayEntry(weekday: 3, kind: .upperB)
        #expect(throws: DomainValidationError.muscleRegionTrainedTooSoon(
            first: 3, second: 4, region: .upperBody)) {
            try document.validate()
        }
    }

    @Test("the rule wraps the week, so Sunday into Monday is checked")
    func recoveryRuleWrapsTheWeek() {
        var document = Seed.program
        document.days[6] = ProgramDayEntry(weekday: 7, kind: .upperB)
        #expect(throws: DomainValidationError.muscleRegionTrainedTooSoon(
            first: 7, second: 1, region: .upperBody)) {
            try document.validate()
        }
    }

    @Test("Zone 2 loads no lifting region, so it may sit beside anything")
    func zone2NeverBlocksALiftingDay() throws {
        #expect(SessionKind.zone2.trainedRegions.isEmpty)
        #expect(SessionKind.fullBody.trainedRegions == [.upperBody, .lowerBody])
        try Seed.historicalProgram.validate()
    }

    @Test("weekday lookup finds the planned session")
    func weekdayLookup() throws {
        #expect(Seed.program.kind(forWeekday: 1) == .upperA)
        #expect(Seed.program.kind(forWeekday: 3) == .rest)
        #expect(Seed.program.session(forWeekday: 1)?.name == "Upper A")
        #expect(Seed.program.session(forWeekday: 3) == nil)
    }
}
