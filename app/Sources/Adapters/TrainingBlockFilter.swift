import AscensionCore
import FeatureTrain
import Foundation

/// Which calendar events are training blocks.
///
/// Every event in the calendar cannot be handed to `SessionMatcher`: a block is how the
/// matcher decides *which* of several eligible workouts completed the day, so a lunch
/// meeting that happens to overlap a walk would credit the walk. The filter is therefore
/// a rule, and because it is a rule it is pure and tested rather than buried in EventKit.
///
/// An event is a block when its title names a session in the program — "Lower A" — or
/// contains one of ``vocabulary``. All-day events never qualify: they span the whole day
/// and would overlap every workout in it, which is the opposite of what a block is for.
enum TrainingBlockFilter {
    /// Words that mean "this is the training block" without naming the session. Short on
    /// purpose: a long list starts matching "training course" and "walking tour".
    static let vocabulary = ["gym", "lift", "lifting", "workout", "train", "training",
                             "session", "run", "ride", "swim", "cycle", "zone 2"]

    /// The titles that count, built from the program itself so renaming a session in the
    /// program renames what the calendar has to say.
    static func titles(in program: ProgramDocument) -> [String] {
        let names = program.sessions.values.map(\.name)
        let kinds = SessionKind.allCases.map(\.rawValue)
        return (names + kinds + vocabulary).map(normalised)
    }

    static func isBlock(title: String, isAllDay: Bool, titles: [String]) -> Bool {
        guard !isAllDay else { return false }
        let candidate = normalised(title)
        guard !candidate.isEmpty else { return false }
        return titles.contains { !$0.isEmpty && candidate.contains($0) }
    }

    /// Case- and accent-insensitive, so "LOWER A" and "Lower a" are the same block.
    private static func normalised(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
