import AppIntents
import AscensionCore
import Foundation

/// A staple food, as Siri resolves it.
///
/// Only the staples (spec §2), never a USDA lookup: an intent has to resolve a spoken name
/// with no network and no disambiguation screen, and the staples are the closed list that
/// makes that possible. Anything else is logged in the Eat tab, where a search belongs.
struct StapleEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food")
    static let defaultQuery = StapleQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct StapleQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [StapleEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    /// Spoken matching is a case-insensitive substring: "omelette" finds "Omelette, three
    /// eggs" without the user reciting the whole row.
    @MainActor
    func entities(matching string: String) async throws -> [StapleEntity] {
        let needle = string.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: nil)
        return try all().filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .contains(needle)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [StapleEntity] { try all() }

    @MainActor
    private func all() throws -> [StapleEntity] {
        try IntentActions.resolve().staples().map { StapleEntity(id: $0.id, name: $0.name) }
    }
}

/// An exercise from the stored library, for the top-set log.
struct ExerciseEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Exercise")
    static let defaultQuery = ExerciseQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ExerciseQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        let needle = string.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: nil)
        return try all().filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .contains(needle)
        }
    }

    /// The program's own exercises first and in full: the ones a top set is ever logged
    /// against are the ones the program names, and the library behind them is thousands of
    /// rows that Siri should not have to read out.
    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        let names = try IntentActions.resolve().exercises()
        return Seed.programExercises.compactMap { exercise in
            ExerciseEntity(id: exercise.id, name: names[exercise.id] ?? exercise.name)
        }
    }

    @MainActor
    private func all() throws -> [ExerciseEntity] {
        try IntentActions.resolve().exercises()
            .map { ExerciseEntity(id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
    }
}
