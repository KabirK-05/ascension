import Foundation

/// Rule 1.3, made mechanical: a label is a noun, at most two words, and never a
/// sentence. Every component in this module checks its own label against this
/// in debug builds, so a banned subtitle trips in the simulator rather than in
/// review.
public enum LabelRule {

    /// The longest a compliant label can be. Two words that need more than this
    /// are a sentence wearing a disguise.
    public static let characterLimit = 24

    /// Characters that only appear when prose has crept in.
    private static let prosePunctuation: Set<Character> = [".", ",", ":", ";", "!", "?", "—"]

    public static func isCompliant(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= characterLimit else { return false }
        guard !trimmed.contains(where: prosePunctuation.contains) else { return false }
        return trimmed.split(whereSeparator: \.isWhitespace).count <= 2
    }

    /// Fails the build's debug run rather than shipping the subtitle.
    static func check(_ label: String, file: StaticString = #fileID, line: UInt = #line) {
        assert(
            isCompliant(label),
            "DESIGN_RULES §1.3: '\(label)' is not a label. Two words, a noun, no sentence.",
            file: file,
            line: line
        )
    }
}
