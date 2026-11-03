import AscensionCore
import Foundation

/// The three mutable documents, exactly as `docs/EXPORT_SCHEMA.md` §2 names them.
public struct ExportDocuments: Codable, Hashable, Sendable {
    public var goalSettings: GoalSettingsDocument
    public var program: ProgramDocument
    public var flags: FlagsDocument

    public init(goalSettings: GoalSettingsDocument, program: ProgramDocument,
                flags: FlagsDocument) {
        self.goalSettings = goalSettings
        self.program = program
        self.flags = flags
    }
}

/// Everything an export reads, as value types.
///
/// The app assembles this from SwiftData and hands it over; `ExportKit` never touches a
/// store, a network or a framework of its own. Only the two things a `DayRollup` cannot
/// carry travel separately — the per-meal diary and the open suggestions — because
/// every other entity in `export.json` is a projection of the rollups.
public struct ExportSnapshot: Hashable, Sendable {
    /// One per day. Sorted on the way in, so every file this produces is date-ordered.
    public var rollups: [DayRollup]
    public var documents: ExportDocuments
    public var meals: [MealEntry]
    public var suggestions: [OpenSuggestion]
    /// `exerciseId` → display name, for `daily-log.md`. The exercise library is another
    /// ticket's (ASC-8), so an id with no entry falls back to a readable form of itself.
    public var exerciseNames: [String: String]

    public init(rollups: [DayRollup], documents: ExportDocuments,
                meals: [MealEntry] = [], suggestions: [OpenSuggestion] = [],
                exerciseNames: [String: String] = [:]) {
        self.rollups = rollups.sorted { $0.date < $1.date }
        self.documents = documents
        self.meals = meals.sorted { left, right in
            left.date == right.date
                ? MealKind.exportOrder(left.meal) < MealKind.exportOrder(right.meal)
                : left.date < right.date
        }
        self.suggestions = suggestions.sorted { $0.id < $1.id }
        self.exerciseNames = exerciseNames
    }
}

extension MealKind {
    /// Meals sort through the day rather than alphabetically, which is the order both
    /// `meals.csv` and the `daily-log.md` food block read in.
    static func exportOrder(_ meal: MealKind) -> Int {
        switch meal {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }
}

extension ExportSnapshot {
    public var workoutRows: [WorkoutRow] {
        rollups.flatMap { rollup in
            rollup.training.workouts.map { WorkoutRow(date: rollup.date, workout: $0) }
        }
    }

    public var topSetRows: [TopSetRow] {
        rollups.flatMap { rollup in
            rollup.training.topSets.map { TopSetRow(date: rollup.date, topSet: $0) }
        }
    }

    public var checkInRows: [CheckInRow] {
        rollups.compactMap { rollup in
            rollup.checkIn.map { CheckInRow(date: rollup.date, checkIn: $0) }
        }
    }

    public var readinessRows: [ReadinessRow] {
        rollups.compactMap { rollup in
            rollup.readiness.map { ReadinessRow(date: rollup.date, readiness: $0) }
        }
    }

    public var sleepRows: [SleepRow] {
        rollups.map { SleepRow(date: $0.date, sleep: $0.sleep) }.filter(\.isMeasured)
    }

    public var weightRows: [WeightRow] {
        rollups.map { WeightRow(date: $0.date, body: $0.body) }.filter(\.isMeasured)
    }

    public func meals(on date: CalendarDate) -> [MealEntry] {
        meals.filter { $0.date == date }
    }

    /// The display name for an exercise: the supplied one, else a readable form of the
    /// id (`Goblet_Squat` → `goblet squat`), which keeps all-caps tokens like `DB`.
    public func exerciseName(_ id: String) -> String {
        if let name = exerciseNames[id] { return name }
        return id.split(separator: "_")
            .map { word in word.allSatisfy { $0.isUppercase || !$0.isLetter }
                ? String(word) : word.lowercased() }
            .joined(separator: " ")
    }
}
