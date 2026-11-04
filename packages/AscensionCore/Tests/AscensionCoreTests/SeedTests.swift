import Foundation
import Testing

@testable import AscensionCore

@Suite("the seed matches spec §2 and §3")
struct SeedTests {
    @Test("goal settings carry the spec §2 numbers")
    func goalSettingsMatchSpec() {
        let targets = Seed.goalSettings.targets
        #expect(targets.kcal == 2200)
        #expect(targets.proteinG == 150)
        #expect(targets.proteinMinG == 140)
        #expect(targets.fatMinG == 60)
        #expect(targets.fatMaxG == 70)
        #expect(targets.steps == 10_000)
        #expect(targets.sleepMinutes == 450)
        #expect(Seed.goalSettings.body.goalWeightKg == 68.0)
        #expect(Seed.goalSettings.timezone == "America/Toronto")
    }

    @Test("the seeded goal settings satisfy every invariant")
    func goalSettingsValidate() throws {
        try Seed.goalSettings.validate()
    }

    @Test("the current program is the four-day Upper/Lower split")
    func programIsTheCurrentSplit() {
        #expect(Seed.program.name == "Upper/Lower 4-day")
        #expect(Seed.program.days.count == 7)
        #expect(Seed.program.days.map(\.kind) == [.upperA, .lowerA, .rest, .upperB,
                                                  .lowerB, .rest, .rest])
        #expect(Seed.program.progression.rule == .rir2)
        #expect(Seed.program.progression.incrementKg == 2.5)
    }

    @Test("every lifting slot defaults to 3 sets of 10–12 unless it is a hold")
    func defaultLoadingIsThreeByTenToTwelve() {
        let repRanged = Seed.program.sessions.values
            .flatMap(\.exercises)
            .filter { !$0.finisher && $0.repsHigh > 1 }
        #expect(!repRanged.isEmpty)
        for exercise in repRanged {
            #expect(exercise.sets == 3)
            #expect(exercise.repsLow == 10)
            #expect(exercise.repsHigh == 12)
        }
    }

    @Test("the incline-walk finisher lands on exactly two lifting days a week")
    func finisherRunsTwiceAWeek() {
        #expect(Seed.program.finisher.kind == .inclineWalk)
        #expect(Seed.program.finisher.minutes == 15)
        #expect(Seed.program.finisher.daysPerWeek == 2)
        #expect(Seed.program.finisherWeekdays.count == Seed.program.finisher.daysPerWeek)
        for weekday in Seed.program.finisherWeekdays {
            #expect(Seed.program.kind(forWeekday: weekday)?.isTrainingDay == true)
        }
    }

    @Test("the current program passes every program invariant")
    func programValidates() throws {
        try Seed.program.validate()
    }

    @Test("the historical full-body plus Zone 2 shape is expressible and valid")
    func historicalProgramValidates() throws {
        try Seed.historicalProgram.validate()
        #expect(Seed.historicalProgram.days.map(\.kind) == [.fullBody, .rest, .zone2,
                                                            .fullBody, .rest, .zone2,
                                                            .rest])
        #expect(Seed.historicalProgram.sessions.keys.sorted { $0.rawValue < $1.rawValue }
            == [SessionKind.fullBody, SessionKind.zone2])
        #expect(Seed.historicalProgram.finisherWeekdays.isEmpty)
    }

    @Test("every exercise a session plans has a seeded library entry")
    func programExercisesAreSeeded() {
        let seeded = Set(Seed.programExercises.map(\.id))
        for program in [Seed.program, Seed.historicalProgram] {
            for exercise in program.sessions.values.flatMap(\.exercises) {
                #expect(seeded.contains(exercise.exerciseId),
                        "\(exercise.exerciseId) is planned but not seeded")
            }
        }
    }

    @Test("every seeded exercise carries cues and common mistakes")
    func exercisesCarryTheCuratedLayer() {
        #expect(Seed.programExercises.count >= 15)
        for exercise in Seed.programExercises {
            #expect(!exercise.cues.isEmpty, "\(exercise.id) has no cues")
            #expect(!exercise.commonMistakes.isEmpty, "\(exercise.id) has no mistakes")
            #expect(!exercise.primaryMuscles.isEmpty)
        }
    }

    @Test("exercise ids are unique and shaped like free-exercise-db ids")
    func exerciseIdsAreWellFormed() {
        let ids = Seed.programExercises.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(!id.isEmpty)
            #expect(!id.contains(" "))
            #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" })
        }
    }

    @Test("the four staples are seeded with unique ids")
    func staplesAreSeeded() {
        #expect(Seed.stapleFoods.count == 4)
        #expect(Set(Seed.stapleFoods.map(\.id)).count == 4)
        for food in Seed.stapleFoods {
            #expect(food.source == .staple)
            #expect(food.servingGrams != nil)
        }
    }

    @Test("each staple's serving hits the kcal and protein spec §2 quotes",
          arguments: [("staple_omelette_toast", 430.0, 24.0),
                      ("staple_chicken_breast_rice", 650.0, 55.0),
                      ("staple_chicken_thighs_potatoes", 700.0, 50.0),
                      ("staple_milk_bournvita", 250.0, 10.0)])
    func stapleServingsMatchSpec(id: String, kcal: Double, proteinG: Double) throws {
        let food = try #require(Seed.stapleFoods.first { $0.id == id })
        let macros = try #require(food.servingMacros)
        #expect(abs(macros.kcal - kcal) <= 5)
        #expect(abs(macros.proteinG - proteinG) <= 1)
    }

    @Test("a staple's macros add up to its calories")
    func stapleMacrosAreInternallyConsistent() throws {
        for food in Seed.stapleFoods {
            let macros = try #require(food.servingMacros)
            let fromMacros = macros.proteinG * 4 + macros.fatG * 9 + macros.carbsG * 4
            #expect(abs(fromMacros - macros.kcal) <= 15, "\(food.id) does not add up")
        }
    }
}

@Suite("the hard dietary constraint holds everywhere")
struct DietaryConstraintTests {
    static let banned = ["pork", "beef", "bacon", "ham", "steak", "mince",
                         "sausage", "salami", "pepperoni", "prosciutto"]

    @Test("excluded meats always contain pork and beef")
    func excludedMeatsAreComplete() {
        #expect(Seed.goalSettings.dietaryRules.excludedMeats.contains("pork"))
        #expect(Seed.goalSettings.dietaryRules.excludedMeats.contains("beef"))
    }

    @Test("no seeded food names a banned meat")
    func noSeededFoodIsBanned() {
        for food in Seed.stapleFoods {
            let name = food.name.lowercased()
            for meat in Self.banned {
                #expect(!name.contains(meat), "\(food.name) names \(meat)")
            }
        }
    }

    @Test("milk with Bournvita is the only dairy allowed")
    func dairyIsLimitedToBournvita() {
        #expect(Seed.goalSettings.dietaryRules.allowedDairy == ["milk_bournvita"])
        #expect(Seed.goalSettings.dietaryRules.noLiquidCalories)
    }

    @Test("goal settings that drop pork or beef are rejected",
          arguments: [[String](), ["pork"], ["beef"], ["chicken"]])
    func droppingAnExcludedMeatFails(_ excluded: [String]) {
        var document = Seed.goalSettings
        document.dietaryRules.excludedMeats = excluded
        #expect(throws: DomainValidationError.self) { try document.validate() }
    }
}
