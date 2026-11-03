import Foundation
import SwiftData
import Testing

@testable import AscensionCore

@MainActor
@Suite("the SwiftData models hold the contract shape")
struct PersistenceTests {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AscensionSchema.schema,
                                           configurations: configuration)
        return ModelContext(container)
    }

    @Test("every §7 entity is in the schema")
    func schemaCoversSpecSection7() throws {
        let names = AscensionSchema.models.map { String(describing: $0) }.sorted()
        #expect(names == ["CheckIn", "Exercise", "ExportManifest", "FoodItem",
                          "GoalSettings", "MealLog", "Program", "ProgramDay",
                          "ReadinessSnapshot", "SessionExercise", "SessionTemplate",
                          "TopSetLog"])
        _ = try makeContext()
    }

    @Test("installing the seed writes goals, the program, the staples and the library")
    func seedInstalls() throws {
        let context = try makeContext()
        try Seed.install(into: context)

        #expect(try context.fetch(FetchDescriptor<GoalSettings>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Program>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FoodItem>()).count == 4)
        #expect(try context.fetch(FetchDescriptor<Exercise>()).count
            == Seed.programExercises.count)

        let program = try #require(try context.fetch(FetchDescriptor<Program>()).first)
        #expect(program.isActive)
        #expect(program.days.count == 7)
        #expect(program.sessions.count == 4)
    }

    @Test("installing twice does not duplicate or overwrite")
    func seedIsIdempotent() throws {
        let context = try makeContext()
        try Seed.install(into: context)

        let settings = try #require(try context.fetch(FetchDescriptor<GoalSettings>()).first)
        settings.kcal = 2000
        try context.save()

        try Seed.install(into: context)

        let all = try context.fetch(FetchDescriptor<GoalSettings>())
        #expect(all.count == 1)
        #expect(all.first?.kcal == 2000)
        #expect(try context.fetch(FetchDescriptor<Program>()).count == 1)
    }

    @Test("a stored program round-trips back to its document")
    func programModelRoundTripsToDocument() throws {
        let context = try makeContext()
        let stored = Program(document: Seed.program, isActive: true)
        context.insert(stored)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Program>()).first)
        let document = try #require(fetched.document)
        #expect(document == Seed.program)
    }

    @Test("the historical shape round-trips through the store too")
    func historicalProgramModelRoundTrips() throws {
        let context = try makeContext()
        context.insert(Program(document: Seed.historicalProgram))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Program>()).first)
        #expect(fetched.document == Seed.historicalProgram)
    }

    @Test("goal settings round-trip through the store")
    func goalSettingsModelRoundTrips() throws {
        let context = try makeContext()
        context.insert(GoalSettings(document: Seed.goalSettings))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<GoalSettings>()).first)
        #expect(fetched.document == Seed.goalSettings)
    }

    @Test("a meal log keeps the macros it was written with")
    func mealLogStoresItsOwnMacros() throws {
        let context = try makeContext()
        let staple = try #require(Seed.stapleFoods.first)
        let food = FoodItem(dto: staple)
        let macros = staple.macros(forGrams: 200)
        context.insert(food)
        context.insert(MealLog(date: CalendarDate.literal("2026-11-09"), meal: .lunch,
                               grams: 200, macros: macros, foodItem: food,
                               foodName: staple.name))
        try context.save()

        let log = try #require(try context.fetch(FetchDescriptor<MealLog>()).first)
        #expect(log.meal == .lunch)
        #expect(log.calendarDate?.rawValue == "2026-11-09")
        #expect(abs(log.macros.kcal - macros.kcal) < 0.001)
        #expect(log.foodItem?.id == staple.id)
    }

    @Test("a check-in and a readiness snapshot convert to their rollup groups")
    func recoveryModelsConvertToRollups() throws {
        let context = try makeContext()
        let date = CalendarDate.literal("2026-11-09")
        let soreness = Soreness(back: .mild, quads: .sore)
        context.insert(CheckIn(date: date, energy: 4, soreness: soreness))
        context.insert(ReadinessSnapshot(date: date, score: 82, verdict: .trainAsPlanned,
                                         reasons: ["slept 7h42", "HRV near baseline"]))
        try context.save()

        let checkIn = try #require(try context.fetch(FetchDescriptor<CheckIn>()).first)
        #expect(checkIn.rollup == CheckInRollup(energy: 4, soreness: soreness))
        #expect(checkIn.soreness.level(for: .quads) == .sore)
        #expect(checkIn.soreness.byGroup.count == MuscleGroup.allCases.count)

        let readiness = try #require(
            try context.fetch(FetchDescriptor<ReadinessSnapshot>()).first)
        #expect(readiness.rollup.verdict == .trainAsPlanned)
        #expect(readiness.rollup.score == 82)
    }

    @Test("a top-set log converts to the rollup's top set")
    func topSetModelConverts() throws {
        let context = try makeContext()
        context.insert(TopSetLog(date: CalendarDate.literal("2026-11-09"),
                                 exerciseId: SeedExerciseId.gobletSquat,
                                 weightKg: 24, reps: 12, sessionType: .lowerA))
        try context.save()

        let log = try #require(try context.fetch(FetchDescriptor<TopSetLog>()).first)
        #expect(log.topSet == TopSet(exerciseId: "Goblet_Squat", weightKg: 24, reps: 12))
        #expect(log.sessionType == .lowerA)
    }

    @Test("an export manifest records the schema version and its counts")
    func exportManifestStoresCounts() throws {
        let context = try makeContext()
        context.insert(ExportManifest(
            exportedAt: Timestamp.literal("2026-11-09T23:30:00-05:00"),
            recordCounts: ["rollups": 28, "meals": 94]))
        try context.save()

        let manifest = try #require(try context.fetch(FetchDescriptor<ExportManifest>()).first)
        #expect(manifest.schemaVersion == AscensionCoreModule.schemaVersion)
        #expect(manifest.recordCounts["rollups"] == 28)
    }

    @Test("a stored food item round-trips to its DTO")
    func foodItemRoundTrips() throws {
        for staple in Seed.stapleFoods {
            #expect(FoodItem(dto: staple).dto == staple)
        }
    }

    @Test("a stored exercise round-trips to its DTO")
    func exerciseRoundTrips() throws {
        for exercise in Seed.programExercises {
            #expect(Exercise(dto: exercise).dto == exercise)
        }
    }
}
