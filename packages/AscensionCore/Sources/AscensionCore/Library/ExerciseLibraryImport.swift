import Foundation

/// Why a bundled row was rejected, or the bundle could not be read at all.
public enum ExerciseLibraryError: Error, Hashable, Sendable {
    case resourceMissing(String)
    case noUsableRecords
}

extension ExerciseLibraryError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .resourceMissing(let name):
            return "the exercise library resource '\(name)' is not in the bundle"
        case .noUsableRecords:
            return "the exercise library decoded but held no usable record"
        }
    }
}

/// Turns the bundled free-exercise-db slice into `ExerciseDTO`s.
///
/// Two sources meet here. The dataset owns what it is good at — step-by-step
/// instructions and demo images — and the app's curated layer (`Seed.programExercises`,
/// spec §F2) owns the name, the muscles, the equipment, the key cues and the common
/// mistakes for the program lifts. The curated side wins every overlap, so a dataset
/// refresh can never rename a program exercise or drop a cue.
public enum ExerciseLibraryImport {

    /// A dataset row carries far more prose than a card can show, and an untrusted
    /// file could carry far more than that.
    static let instructionLimit = 20

    /// Merges records with the curated layer, newest-first wins on duplicate ids.
    ///
    /// Records whose id or name is blank are dropped, as are image refs that are not
    /// a plain `<folder>/<file>` relative path — the refs are resolved against the
    /// bundle, so a `..` in one would be a path-traversal read.
    public static func exercises(
        from records: [ExerciseLibraryRecord],
        curated: [ExerciseDTO] = Seed.programExercises
    ) -> [ExerciseDTO] {
        let curatedById = Dictionary(curated.map { ($0.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var imported: [ExerciseDTO] = []

        for record in records {
            let datasetId = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !datasetId.isEmpty, !name.isEmpty else { continue }

            let id = ExerciseLibraryMapping.programIds[datasetId] ?? datasetId
            guard seen.insert(id).inserted else { continue }

            let instructions = record.instructions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(instructionLimit)
            let imageRefs = record.images.filter(isSafeImageRef)

            if let curated = curatedById[id] {
                var merged = curated
                merged.instructions = Array(instructions)
                merged.imageRefs = imageRefs
                imported.append(merged)
            } else {
                imported.append(ExerciseDTO(
                    id: id,
                    name: name,
                    primaryMuscles: record.primaryMuscles,
                    secondaryMuscles: record.secondaryMuscles,
                    equipment: record.equipment,
                    instructions: Array(instructions),
                    imageRefs: imageRefs))
            }
        }

        // A curated exercise the dataset has no row for still belongs in the library:
        // it is on the program, and its cues are the reason the layer exists.
        for exercise in curated where !seen.contains(exercise.id) {
            seen.insert(exercise.id)
            imported.append(exercise)
        }

        return imported.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Decodes a free-exercise-db `exercises.json` payload.
    public static func records(from data: Data) throws -> [ExerciseLibraryRecord] {
        try JSONDecoder().decode([ExerciseLibraryRecord].self, from: data)
    }

    static func isSafeImageRef(_ ref: String) -> Bool {
        let components = ref.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2 else { return false }
        return components.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && !part.contains(":")
        }
    }
}
