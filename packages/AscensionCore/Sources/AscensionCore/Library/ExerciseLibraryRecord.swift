import Foundation

/// One row of free-exercise-db, as bundled (`Tools/build-exercise-library.sh`).
///
/// This is the wire shape of a public dataset, so every field is treated as
/// untrusted: decoding accepts what the file says and `ExerciseLibraryImport`
/// decides what is usable. Only the fields the app shows are carried.
public struct ExerciseLibraryRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var equipment: String?
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var instructions: [String]
    public var images: [String]

    public init(id: String, name: String, equipment: String? = nil,
                primaryMuscles: [String] = [], secondaryMuscles: [String] = [],
                instructions: [String] = [], images: [String] = []) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
        self.images = images
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment)
        primaryMuscles = try container.decodeIfPresent([String].self, forKey: .primaryMuscles) ?? []
        secondaryMuscles = try container
            .decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? []
        instructions = try container.decodeIfPresent([String].self, forKey: .instructions) ?? []
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
    }
}
