import Foundation

/// free-exercise-db writes its muscles and equipment in lower case ("body only",
/// "cardiovascular system"). Sentence case reads as a value; `.capitalized` would
/// turn the same strings into "Body Only", which reads as a proper noun.
extension String {
    var sentenceCased: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
