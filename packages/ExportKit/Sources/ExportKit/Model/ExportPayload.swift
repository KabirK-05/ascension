import AscensionCore
import Foundation

/// `export.json` — the full export, one file (`docs/EXPORT_SCHEMA.md` §4).
///
/// `schemaVersion` leads, then `exportedAt` and `recordCounts`, then one array per
/// entity. Field names are the contract's own: the Worker and both MCP servers read
/// these same names, so a rename here is a silent break there and a `schemaVersion`
/// bump in the same PR.
public struct ExportPayload: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Timestamp
    /// Rows written per entity, keyed by the array names below.
    public var recordCounts: [String: Int]

    public var rollups: [DayRollup]
    public var documents: ExportDocuments
    public var meals: [MealEntry]
    public var topSets: [TopSetRow]
    public var checkIns: [CheckInRow]
    public var readiness: [ReadinessRow]
    public var workouts: [WorkoutRow]
    public var sleep: [SleepRow]
    public var weight: [WeightRow]
    public var suggestions: [OpenSuggestion]

    public init(snapshot: ExportSnapshot, exportedAt: Timestamp,
                schemaVersion: Int = ExportKitModule.schemaVersion) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.rollups = snapshot.rollups
        self.documents = snapshot.documents
        self.meals = snapshot.meals
        self.topSets = snapshot.topSetRows
        self.checkIns = snapshot.checkInRows
        self.readiness = snapshot.readinessRows
        self.workouts = snapshot.workoutRows
        self.sleep = snapshot.sleepRows
        self.weight = snapshot.weightRows
        self.suggestions = snapshot.suggestions
        self.recordCounts = [
            "rollups": rollups.count,
            "meals": meals.count,
            "topSets": topSets.count,
            "checkIns": checkIns.count,
            "readiness": readiness.count,
            "workouts": workouts.count,
            "sleep": sleep.count,
            "weight": weight.count,
            "suggestions": suggestions.count
        ]
    }
}

extension ExportPayload {
    /// The encoder every JSON file in the export uses.
    ///
    /// `sortedKeys` is not cosmetic: `ProgramDocument.sessions` is a dictionary, so
    /// without it the same data would encode to different bytes each run — which would
    /// make `export.json` churn in iCloud and golden-file tests meaningless.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public func encoded() throws -> Data {
        var data = try Self.encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
