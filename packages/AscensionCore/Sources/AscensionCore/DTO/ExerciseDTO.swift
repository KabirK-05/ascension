import Foundation

/// An exercise in the library (spec §7).
///
/// `id` is a free-exercise-db id. `instructions` and `imageRefs` stay empty until the
/// library import (ASC-8) fills them; `cues` and `commonMistakes` are the app's own
/// curated layer and are seeded for the program exercises first (spec §F2).
public struct ExerciseDTO: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var equipment: String?
    public var instructions: [String]
    public var imageRefs: [String]
    public var cues: [String]
    public var commonMistakes: [String]

    public init(id: String, name: String, primaryMuscles: [String],
                secondaryMuscles: [String] = [], equipment: String? = nil,
                instructions: [String] = [], imageRefs: [String] = [],
                cues: [String] = [], commonMistakes: [String] = []) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instructions = instructions
        self.imageRefs = imageRefs
        self.cues = cues
        self.commonMistakes = commonMistakes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(primaryMuscles, forKey: .primaryMuscles)
        try container.encode(secondaryMuscles, forKey: .secondaryMuscles)
        try container.encodeNullable(equipment, forKey: .equipment)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(imageRefs, forKey: .imageRefs)
        try container.encode(cues, forKey: .cues)
        try container.encode(commonMistakes, forKey: .commonMistakes)
    }
}
