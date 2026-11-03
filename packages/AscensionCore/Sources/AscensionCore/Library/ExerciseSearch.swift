import Foundation

/// Searching and grouping the library. Pure functions over value types, so the
/// library screen holds no logic of its own.
public enum ExerciseSearch {

    /// Where a term matched. Lower sorts first, so a name beats a muscle and a
    /// muscle beats a piece of equipment.
    enum Rank: Int, Comparable {
        case namePrefix = 0
        case nameContains = 1
        case primaryMuscle = 2
        case secondaryMuscle = 3
        case equipment = 4

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Exercises matching `term` by name, muscle or equipment.
    ///
    /// Case- and diacritic-insensitive, and a blank term returns everything, so the
    /// screen does not need a separate "not searching" branch.
    public static func matches(_ term: String, in exercises: [ExerciseDTO]) -> [ExerciseDTO] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return exercises }

        return exercises
            .compactMap { exercise -> (Rank, ExerciseDTO)? in
                guard let rank = rank(of: exercise, for: needle) else { return nil }
                return (rank, exercise)
            }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0
                    ? lhs.1.name.localizedCaseInsensitiveCompare(rhs.1.name) == .orderedAscending
                    : lhs.0 < rhs.0
            }
            .map(\.1)
    }

    /// The library by primary muscle, muscles alphabetical and exercises by name.
    ///
    /// An exercise with no primary muscle is dropped rather than filed under a
    /// heading the data does not support.
    public static func groupedByPrimaryMuscle(
        _ exercises: [ExerciseDTO]
    ) -> [(muscle: String, exercises: [ExerciseDTO])] {
        var buckets: [String: [ExerciseDTO]] = [:]
        for exercise in exercises {
            guard let muscle = exercise.primaryMuscles.first, !muscle.isEmpty else { continue }
            buckets[muscle, default: []].append(exercise)
        }
        return buckets
            .map { muscle, found in
                (muscle, found.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                })
            }
            .sorted { $0.muscle.localizedCaseInsensitiveCompare($1.muscle) == .orderedAscending }
    }

    /// Every primary muscle in the library, alphabetical. The empty-result control.
    public static func primaryMuscles(in exercises: [ExerciseDTO]) -> [String] {
        Set(exercises.compactMap(\.primaryMuscles.first))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func rank(of exercise: ExerciseDTO, for needle: String) -> Rank? {
        if contains(exercise.name, needle, anchored: true) { return .namePrefix }
        if contains(exercise.name, needle) { return .nameContains }
        if exercise.primaryMuscles.contains(where: { contains($0, needle) }) {
            return .primaryMuscle
        }
        if exercise.secondaryMuscles.contains(where: { contains($0, needle) }) {
            return .secondaryMuscle
        }
        if let equipment = exercise.equipment, contains(equipment, needle) { return .equipment }
        return nil
    }

    private static func contains(_ haystack: String, _ needle: String,
                                 anchored: Bool = false) -> Bool {
        let options: String.CompareOptions = anchored
            ? [.caseInsensitive, .diacriticInsensitive, .anchored]
            : [.caseInsensitive, .diacriticInsensitive]
        return haystack.range(of: needle, options: options) != nil
    }
}
