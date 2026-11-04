import AscensionCore
import Foundation

/// The kind-specific payloads of `docs/EXPORT_SCHEMA.md` §3, typed.
///
/// `Mutation.payload` is stored verbatim as JSON because its shape depends on `kind`;
/// these are the shapes, decoded once at the edge of the applier so a handler never reads
/// a dictionary by hand.
public enum MutationPayload {
    /// A partial `goalSettings.targets` — only the fields Muse set are present.
    public struct TargetsPatch: Codable, Hashable, Sendable {
        public var kcal: Int?
        public var proteinG: Int?
        public var proteinMinG: Int?
        public var fatMinG: Int?
        public var fatMaxG: Int?
        public var steps: Int?
        public var sleepMinutes: Int?

        /// `targets` with the patch applied. The document's own `validate()` still has the
        /// last word: a patch that breaks the fat floor is refused, never clamped.
        public func applied(to targets: GoalTargets) -> GoalTargets {
            GoalTargets(kcal: kcal ?? targets.kcal,
                        proteinG: proteinG ?? targets.proteinG,
                        proteinMinG: proteinMinG ?? targets.proteinMinG,
                        fatMinG: fatMinG ?? targets.fatMinG,
                        fatMaxG: fatMaxG ?? targets.fatMaxG,
                        steps: steps ?? targets.steps,
                        sleepMinutes: sleepMinutes ?? targets.sleepMinutes)
        }
    }

    /// The whole `program` body. `version`, `updatedAt` and `updatedBy` are not part of a
    /// body on the wire — they are columns on the `documents` table.
    public struct ProgramBody: Codable, Hashable, Sendable {
        public var name: String
        public var days: [ProgramDayEntry]
        public var sessions: [SessionKind: SessionTemplateEntry]
        public var progression: ProgressionSettings
        public var finisher: FinisherSettings
        public var deload: DeloadSettings
    }

    public struct Staples: Codable, Hashable, Sendable {
        public var staples: [FoodItemDTO]
    }

    public struct FlagChange: Codable, Hashable, Sendable {
        public var key: String
        public var value: JSONValue
    }

    public struct AcceptedSuggestion: Codable, Hashable, Sendable {
        public var suggestionId: String
    }

    /// One line of a logged meal. `foodItemId` is absent for a food Muse described rather
    /// than picked from the staples.
    public struct MealItem: Codable, Hashable, Sendable {
        public var foodItemId: String?
        public var name: String
        public var grams: Double
        public var kcal: Double
        public var proteinG: Double
        public var fatG: Double
        public var carbsG: Double
    }

    public struct LoggedMealPayload: Codable, Hashable, Sendable {
        public var date: CalendarDate
        public var meal: MealKind
        public var items: [MealItem]

        /// The meal's totals, which is what both HealthKit and the rollup want.
        public var totals: MealTotals {
            MealTotals(kcal: items.reduce(0) { $0 + $1.kcal },
                       proteinG: items.reduce(0) { $0 + $1.proteinG },
                       fatG: items.reduce(0) { $0 + $1.fatG },
                       carbsG: items.reduce(0) { $0 + $1.carbsG })
        }
    }

    public struct MealTotals: Hashable, Sendable {
        public var kcal: Double
        public var proteinG: Double
        public var fatG: Double
        public var carbsG: Double
    }

    public struct Water: Codable, Hashable, Sendable {
        public var date: CalendarDate
        public var ml: Double
    }

    public struct TopSetPayload: Codable, Hashable, Sendable {
        public var date: CalendarDate
        public var exerciseId: String
        public var weightKg: Double
        public var reps: Int

        public var topSet: TopSet {
            TopSet(exerciseId: exerciseId, weightKg: weightKg, reps: reps)
        }
    }

    public struct CheckInPayload: Codable, Hashable, Sendable {
        public var date: CalendarDate
        public var energy: Int
        public var soreness: Soreness
    }

    public struct ScheduledWorkout: Codable, Hashable, Sendable {
        public var date: CalendarDate
        public var sessionKind: SessionKind
    }
}

extension Mutation {
    /// Decodes this mutation's payload as `type`.
    ///
    /// Round-tripped through the shared coder rather than read key by key: a payload whose
    /// shape has drifted from the contract then fails here, loudly, instead of applying
    /// half of what Muse asked for.
    public func payload<T: Decodable>(as type: T.Type) throws -> T {
        let data = try SyncCoding.encode(payload)
        return try SyncCoding.decode(type, from: data)
    }
}
