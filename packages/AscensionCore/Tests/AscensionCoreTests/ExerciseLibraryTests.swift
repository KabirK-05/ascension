import Foundation
import Testing

@testable import AscensionCore

@Suite("the bundled exercise library (spec §F2, §10)")
struct ExerciseLibraryTests {

    @Test("the bundled catalogue decodes and carries every allowlisted row")
    func bundleDecodes() throws {
        let records = try ExerciseLibraryImport.records(from: try ExerciseLibrary.catalogData())
        #expect(records.count == 64)
        #expect(records.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        #expect(records.allSatisfy { !$0.instructions.isEmpty })
        #expect(records.allSatisfy { $0.images.count == 2 })
    }

    @Test("the library is the catalogue plus nothing invented")
    func libraryIsTheCatalogue() throws {
        let library = try ExerciseLibrary.bundled()
        #expect(library.count == 64)
        #expect(Set(library.map(\.id)).count == library.count)
        let names = library.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test("every program exercise id survives the import")
    func programIdsSurvive() throws {
        let byId = Dictionary(try ExerciseLibrary.bundled().map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        for curated in Seed.programExercises {
            let imported = try #require(byId[curated.id], "\(curated.id) missing from the library")
            #expect(imported.name == curated.name)
            #expect(imported.equipment == curated.equipment)
            #expect(imported.primaryMuscles == curated.primaryMuscles)
            #expect(imported.cues == curated.cues)
            #expect(imported.commonMistakes == curated.commonMistakes)
            #expect(!imported.instructions.isEmpty, "\(curated.id) has no instructions")
            #expect(imported.imageRefs.count == 2, "\(curated.id) has no demo images")
        }
    }

    @Test("the mapping covers every program exercise exactly once")
    func mappingIsTotal() {
        let programIds = Set(Seed.programExercises.map(\.id))
        #expect(Set(ExerciseLibraryMapping.databaseIds.keys) == programIds)
        let datasetIds = ExerciseLibraryMapping.databaseIds.values
        #expect(Set(datasetIds).count == datasetIds.count)
        #expect(ExerciseLibraryMapping.programIds.count == programIds.count)
    }

    @Test("every bundled demo image resolves to a real file")
    func imagesResolve() throws {
        let refs = try ExerciseLibrary.bundled().flatMap(\.imageRefs)
        #expect(refs.count == 128)
        for ref in refs {
            #expect(ExerciseLibrary.imageURL(for: ref) != nil, "\(ref) is not bundled")
        }
    }

    @Test("a traversal or absolute image ref resolves to nothing")
    func unsafeImageRefsAreRejected() {
        for ref in ["../../etc/passwd", "/etc/passwd", "Goblet_Squat/../../x.jpg",
                    "Goblet_Squat", "", "a/b/c.jpg", "./0.jpg"] {
            #expect(ExerciseLibrary.imageURL(for: ref) == nil, "\(ref) should not resolve")
            #expect(ExerciseLibraryImport.isSafeImageRef(ref) == false)
        }
        #expect(ExerciseLibraryImport.isSafeImageRef("Goblet_Squat/0.jpg"))
    }
}

@Suite("the import treats the dataset as untrusted input")
struct ExerciseLibraryImportTests {

    private func record(_ id: String, name: String? = nil,
                        instructions: [String] = ["Stand up."],
                        images: [String] = ["X/0.jpg"]) -> ExerciseLibraryRecord {
        ExerciseLibraryRecord(id: id, name: name ?? id, equipment: "dumbbell",
                              primaryMuscles: ["chest"], instructions: instructions,
                              images: images)
    }

    @Test("the curated layer wins every field it owns")
    func curatedLayerWins() {
        let curated = ExerciseDTO(id: "Goblet_Squat", name: "Goblet Squat",
                                  primaryMuscles: ["quadriceps"], equipment: "dumbbell",
                                  cues: ["Chest tall, hips back"],
                                  commonMistakes: ["Heels lifting"])
        let imported = ExerciseLibraryImport.exercises(
            from: [record("Goblet_Squat", name: "Dataset Name",
                          instructions: ["Step one.", "Step two."])],
            curated: [curated])

        #expect(imported.count == 1)
        #expect(imported[0].name == "Goblet Squat")
        #expect(imported[0].primaryMuscles == ["quadriceps"])
        #expect(imported[0].cues == ["Chest tall, hips back"])
        #expect(imported[0].instructions == ["Step one.", "Step two."])
    }

    @Test("a dataset id the program renamed is imported under the program's id")
    func datasetIdIsRemappedToTheProgramId() {
        let imported = ExerciseLibraryImport.exercises(
            from: [record("Stiff-Legged_Dumbbell_Deadlift")], curated: [])
        #expect(imported.map(\.id) == [SeedExerciseId.dbRomanianDeadlift])
    }

    @Test("blank ids and names are dropped, not imported empty")
    func blankRowsAreDropped() {
        let imported = ExerciseLibraryImport.exercises(
            from: [record("  "), record("Ok", name: "   "), record("Fine")], curated: [])
        #expect(imported.map(\.id) == ["Fine"])
    }

    @Test("a duplicate id is taken once")
    func duplicateIdsCollapse() {
        let imported = ExerciseLibraryImport.exercises(
            from: [record("Plank", name: "First"), record("Plank", name: "Second")],
            curated: [])
        #expect(imported.map(\.name) == ["First"])
    }

    @Test("blank instructions are dropped and the rest are trimmed and capped")
    func instructionsAreCleaned() {
        let noisy = ["  Step one.  ", "", "   "] + (1...30).map { "Step \($0)." }
        let imported = ExerciseLibraryImport.exercises(
            from: [record("Plank", instructions: noisy)], curated: [])
        #expect(imported[0].instructions.count == ExerciseLibraryImport.instructionLimit)
        #expect(imported[0].instructions.first == "Step one.")
        #expect(imported[0].instructions.allSatisfy { !$0.isEmpty })
    }

    @Test("an unsafe image ref is stripped and the safe ones kept")
    func unsafeRefsAreStripped() {
        let imported = ExerciseLibraryImport.exercises(
            from: [record("Plank", images: ["Plank/0.jpg", "../x.jpg", "/abs.jpg"])],
            curated: [])
        #expect(imported[0].imageRefs == ["Plank/0.jpg"])
    }

    @Test("a curated exercise the dataset has no row for is still in the library")
    func curatedOnlyExerciseSurvives() {
        let orphan = ExerciseDTO(id: "Incline_Treadmill_Walk", name: "Incline Treadmill Walk",
                                 primaryMuscles: ["cardiovascular system"],
                                 cues: ["Hands off the rails"])
        let imported = ExerciseLibraryImport.exercises(from: [], curated: [orphan])
        #expect(imported.map(\.id) == ["Incline_Treadmill_Walk"])
        #expect(imported[0].cues == ["Hands off the rails"])
    }

    @Test("malformed JSON throws rather than importing a half-read library")
    func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            try ExerciseLibraryImport.records(from: Data("{ not an array }".utf8))
        }
    }

    @Test("a record missing its required keys fails to decode")
    func recordRequiresIdAndName() {
        #expect(throws: (any Error).self) {
            try ExerciseLibraryImport.records(from: Data(#"[{"name": "No id"}]"#.utf8))
        }
    }

    @Test("a record with only id and name decodes with empty collections")
    func recordToleratesMissingOptionalKeys() throws {
        let records = try ExerciseLibraryImport
            .records(from: Data(#"[{"id": "X", "name": "X"}]"#.utf8))
        #expect(records[0].equipment == nil)
        #expect(records[0].primaryMuscles.isEmpty)
        #expect(records[0].instructions.isEmpty)
        #expect(records[0].images.isEmpty)
    }
}

@Suite("the curated cue lookup")
struct ExerciseCuesTests {

    @Test("every program exercise has cues and common mistakes")
    func everyProgramExerciseIsCoached() {
        #expect(ExerciseCues.curatedIds.count == Seed.programExercises.count)
        for exercise in Seed.programExercises {
            let cues = ExerciseCues.cues(for: exercise.id)
            let mistakes = ExerciseCues.commonMistakes(for: exercise.id)
            #expect((2...3).contains(cues.count), "\(exercise.id) has \(cues.count) cues")
            #expect((2...3).contains(mistakes.count),
                    "\(exercise.id) has \(mistakes.count) mistakes")
            #expect(cues.allSatisfy { !$0.isEmpty && $0.count <= 60 })
            #expect(mistakes.allSatisfy { !$0.isEmpty && $0.count <= 60 })
        }
    }

    @Test("the spec §F2 examples are the cues they ask for")
    func specExamplesAreSeeded() {
        #expect(ExerciseCues.cues(for: SeedExerciseId.gobletSquat)
            .contains("Chest tall, hips back"))
        #expect(ExerciseCues.cues(for: SeedExerciseId.dbRomanianDeadlift)
            .contains { $0.contains("Soft knees") && $0.contains("hips to the wall") })
    }

    @Test("a library-only id looks up to nothing rather than trapping")
    func uncuratedIdIsEmpty() {
        #expect(ExerciseCues.curated(for: "Air_Bike") == nil)
        #expect(ExerciseCues.cues(for: "Air_Bike").isEmpty)
        #expect(ExerciseCues.commonMistakes(for: "nonexistent").isEmpty)
    }
}

@Suite("library search")
struct ExerciseSearchTests {

    private let library = [
        ExerciseDTO(id: "A", name: "Goblet Squat", primaryMuscles: ["quadriceps"],
                    secondaryMuscles: ["glutes"], equipment: "dumbbell"),
        ExerciseDTO(id: "B", name: "Front Barbell Squat", primaryMuscles: ["quadriceps"],
                    equipment: "barbell"),
        ExerciseDTO(id: "C", name: "Lying Leg Curls", primaryMuscles: ["hamstrings"],
                    equipment: "machine"),
        ExerciseDTO(id: "D", name: "Plank", primaryMuscles: ["abdominals"],
                    equipment: "body only"),
        ExerciseDTO(id: "E", name: "Barbell Front Raise", primaryMuscles: ["shoulders"],
                    equipment: "barbell")
    ]

    @Test("a blank term is the whole library, untouched")
    func blankTermReturnsEverything() {
        #expect(ExerciseSearch.matches("", in: library).map(\.id) == ["A", "B", "C", "D", "E"])
        #expect(ExerciseSearch.matches("   ", in: library).map(\.id) == ["A", "B", "C", "D", "E"])
    }

    @Test("a name prefix sorts above a name the term appears inside")
    func namePrefixWins() {
        // "Front Barbell Squat" starts with the term; "Barbell Front Raise" only holds it.
        #expect(ExerciseSearch.matches("front", in: library).map(\.id) == ["B", "E"])
    }

    @Test("two equal matches fall back to alphabetical order")
    func equalMatchesSortByName() {
        #expect(ExerciseSearch.matches("squat", in: library).map(\.id) == ["B", "A"])
    }

    @Test("muscle and equipment match, and rank below the name")
    func muscleAndEquipmentMatch() {
        #expect(ExerciseSearch.matches("hamstrings", in: library).map(\.id) == ["C"])
        #expect(ExerciseSearch.matches("dumbbell", in: library).map(\.id) == ["A"])
        #expect(ExerciseSearch.matches("glutes", in: library).map(\.id) == ["A"])
    }

    @Test("search ignores case and diacritics")
    func searchIsForgiving() {
        #expect(ExerciseSearch.matches("GOBLET", in: library).map(\.id) == ["A"])
        #expect(ExerciseSearch.matches("plánk", in: library).map(\.id) == ["D"])
    }

    @Test("no match is an empty result, not the whole library")
    func noMatchIsEmpty() {
        #expect(ExerciseSearch.matches("kettlebell swing", in: library).isEmpty)
    }

    @Test("grouping files each exercise under its primary muscle, alphabetically")
    func groupingIsAlphabetical() {
        let groups = ExerciseSearch.groupedByPrimaryMuscle(library)
        #expect(groups.map(\.muscle) == ["abdominals", "hamstrings", "quadriceps", "shoulders"])
        #expect(groups.first { $0.muscle == "quadriceps" }?.exercises.map(\.name)
            == ["Front Barbell Squat", "Goblet Squat"])
    }

    @Test("an exercise with no primary muscle is left out of the grouping")
    func unmuscledExerciseIsNotGrouped() {
        let odd = ExerciseDTO(id: "Z", name: "Unknown", primaryMuscles: [])
        let groups = ExerciseSearch.groupedByPrimaryMuscle(library + [odd])
        #expect(groups.flatMap(\.exercises).contains { $0.id == "Z" } == false)
    }

    @Test("the bundled library groups into muscles the detail view can head")
    func bundledLibraryGroupsCleanly() throws {
        let library = try ExerciseLibrary.bundled()
        let groups = ExerciseSearch.groupedByPrimaryMuscle(library)
        #expect(groups.flatMap(\.exercises).count == library.count)
        #expect(ExerciseSearch.primaryMuscles(in: library) == groups.map(\.muscle))
    }
}
