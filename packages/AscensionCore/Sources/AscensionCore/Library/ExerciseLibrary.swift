import Foundation

/// The bundled exercise library (spec §F2, §10).
///
/// free-exercise-db is bundled as a package resource, so the library works with the
/// phone in airplane mode and nothing here ever reaches the network — spec §10 asks
/// for exactly that. `Tools/build-exercise-library.sh` regenerates the resource; the
/// slice it cuts is the program's 17 exercises plus the alternatives for each of
/// their movement patterns.
public enum ExerciseLibrary {

    static let resourceDirectory = "ExerciseLibrary"
    static let catalogName = "exercises"
    static let imageDirectory = "Images"

    /// The whole library, curated layer merged in, sorted by name.
    ///
    /// Decoded on every call. The catalogue is 64 rows and the library screen reads it
    /// once, so a cache would only be a second place for it to go stale.
    public static func bundled() throws -> [ExerciseDTO] {
        let records = try ExerciseLibraryImport.records(from: try catalogData())
        let exercises = ExerciseLibraryImport.exercises(from: records)
        guard !exercises.isEmpty else { throw ExerciseLibraryError.noUsableRecords }
        return exercises
    }

    /// The file URL of a demo image, for an `imageRefs` entry.
    ///
    /// `nil` when the ref is not a plain relative path or the file is not bundled —
    /// the dataset lists images the app does not carry, and a caller shows what it
    /// gets rather than assuming two.
    public static func imageURL(for ref: String) -> URL? {
        guard ExerciseLibraryImport.isSafeImageRef(ref) else { return nil }
        let url = resourceRoot?
            .appending(path: imageDirectory, directoryHint: .isDirectory)
            .appending(path: ref, directoryHint: .notDirectory)
        guard let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return url
    }

    static func catalogData() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "\(resourceDirectory)/\(catalogName)",
            withExtension: "json"
        ) else {
            throw ExerciseLibraryError.resourceMissing("\(resourceDirectory)/\(catalogName).json")
        }
        return try Data(contentsOf: url)
    }

    static var resourceRoot: URL? {
        Bundle.module.resourceURL?
            .appending(path: resourceDirectory, directoryHint: .isDirectory)
    }
}
