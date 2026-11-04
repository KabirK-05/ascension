import AscensionCore
import Foundation

@testable import SyncClient

extension Fixture {
    /// ULIDs in ascending order, so a test can assert on application order without the
    /// ids themselves being noise. Crockford base32, 26 characters, as the Worker's
    /// `CHECK (length(id) = 26)` requires.
    enum Ulid {
        static let first = "01JC8X9Y2K3M4N5P6Q7R8S9T01"
        static let second = "01JC8X9Y2K3M4N5P6Q7R8S9T02"
        static let third = "01JC8X9Y2K3M4N5P6Q7R8S9T03"
    }

    static func mutation(id: String, kind: MutationKind, payload: JSONValue,
                         createdAt: String = "2026-11-03T18:00:00-05:00") -> Mutation {
        Mutation(id: id, createdAt: Timestamp.literal(createdAt), actor: .muse, kind: kind,
                 payload: payload)
    }

    static func setTargets(id: String, kcal: Double) -> Mutation {
        mutation(id: id, kind: .setTargets, payload: .object(["kcal": .number(kcal)]))
    }

    /// A `log_meal` exactly as §3 shows it.
    static func logMeal(id: String, date: String = "2026-11-03",
                        meal: String = "lunch") -> Mutation {
        mutation(id: id, kind: .logMeal, payload: .object([
            "date": .string(date),
            "meal": .string(meal),
            "items": .array([
                .object([
                    "foodItemId": .string("staple_chicken_breast_rice"),
                    "name": .string("Chicken breast, rice, vegetables"),
                    "grams": .number(550),
                    "kcal": .number(650),
                    "proteinG": .number(55),
                    "fatG": .number(14),
                    "carbsG": .number(76)
                ])
            ])
        ]))
    }

    static func logWater(id: String, ml: Double = 500) -> Mutation {
        mutation(id: id, kind: .logWater,
                 payload: .object(["date": .string("2026-11-03"), "ml": .number(ml)]))
    }

    static func logTopSet(id: String, weightKg: Double = 26) -> Mutation {
        mutation(id: id, kind: .logTopSet, payload: .object([
            "date": .string("2026-11-03"),
            "exerciseId": .string("Goblet_Squat"),
            "weightKg": .number(weightKg),
            "reps": .number(10)
        ]))
    }

    /// The body of `GET /v1/mutations`, with the mutations in whatever order is given — the
    /// drain must sort them itself.
    static func mutationPage(_ mutations: [Mutation], cursor: String? = nil) throws -> String {
        let page = MutationPage(mutations: mutations, cursor: cursor, schemaVersion: 1)
        return try Golden.pretty(page)
    }

    static func drainer(transport: FakeTransport,
                        state: any SyncStateStore,
                        local: RecordingLocalApplier,
                        health: RecordingHealthWriteBack) -> MutationDrainer {
        MutationDrainer(session: session(transport), endpoint: origin,
                        applier: MutationApplier(local: local, health: health, clock: clock),
                        state: state, clock: clock)
    }
}
