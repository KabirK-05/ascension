import AscensionCore
import Foundation

/// A suggestion the app has raised and the user has not answered yet — a pending
/// calorie adjustment, say (spec §9.1).
///
/// `summary-latest.md` lists these so an assistant reading the folder knows what is
/// waiting on a decision rather than inferring it from the numbers.
public struct OpenSuggestion: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Timestamp
    /// A short machine-readable category, e.g. `calorieAdjustment`.
    public var kind: String
    /// One plain sentence, facts and units inline.
    public var text: String

    public init(id: String, createdAt: Timestamp, kind: String, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
    }
}
