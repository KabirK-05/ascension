import Foundation

/// The app's curated coaching layer, by exercise id (spec §F2).
///
/// The cues and common mistakes themselves live in `Seed.programExercises`, next to the
/// program they belong to. This is the lookup, so a caller holding only an id — a
/// top-set log, a session row, a library detail view — can reach them without walking
/// the array itself.
public enum ExerciseCues {

    /// The curated entry for an exercise, or `nil` when it is library-only.
    public static func curated(for id: String) -> ExerciseDTO? { byId[id] }

    /// Key cues, in the order a lifter should hear them. Empty when uncurated.
    public static func cues(for id: String) -> [String] { byId[id]?.cues ?? [] }

    /// Common mistakes. Empty when uncurated.
    public static func commonMistakes(for id: String) -> [String] {
        byId[id]?.commonMistakes ?? []
    }

    /// Every exercise the curated layer covers.
    public static var curatedIds: Set<String> { Set(byId.keys) }

    private static let byId: [String: ExerciseDTO] = Dictionary(
        Seed.programExercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first })
}
