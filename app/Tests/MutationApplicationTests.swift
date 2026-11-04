import AscensionCore
import ExportKit
import Foundation
import HealthBridge
import SwiftData
import SyncClient
import Testing

@testable import Ascension

/// What happens to the device when Muse writes.
///
/// The drain, the wire and the HealthKit write are all `SyncClient`'s and `HealthBridge`'s,
/// and both are tested in their own packages. What is untested until here is the half the
/// shell owns: whether a mutation lands in the store, and whether a bad one is refused
/// rather than clamped.
@Suite("applying Muse's mutations")
@MainActor
struct MutationApplicationTests {
    private func store() throws -> LocalStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AscensionSchema.schema,
                                           configurations: configuration)
        let store = LocalStore(container: container)
        #expect(store.installSeed())
        return store
    }

    private func applier(_ store: LocalStore) -> StoreMutationApplier {
        let watch = WatchSessionSender(scheduler: UnavailableSessionScheduler(), zones: nil)
        let export = ExportRunnerStub.unavailable(store: store)
        return StoreMutationApplier(
            store: store,
            flags: FlagsStore(defaults: UserDefaults(
                suiteName: "ascension.tests.mutations.\(UUID().uuidString)") ?? .standard),
            watch: watch,
            export: export,
            changes: ChangeLog(url: FileManager.default.temporaryDirectory
                .appending(path: "changes-\(UUID().uuidString).json")),
            now: { HealthDates.fixedNow })
    }

    @Test("a calorie change reaches the store and bumps the version")
    func targetsPatchApplies() async throws {
        let store = try store()
        let before = store.goals
        let patch: MutationPayload.TargetsPatch =
            try Wire.decode(#"{"kcal": \#(before.targets.kcal - 150)}"#)

        try await applier(store).applyTargets(patch, mutationId: "01MUTATION")

        #expect(store.goals.targets.kcal == before.targets.kcal - 150)
        #expect(store.goals.targets.proteinG == before.targets.proteinG)
        #expect(store.goals.version == before.version + 1)
        #expect(store.goals.updatedBy == .muse)
    }

    /// The contract refuses rather than clamps, and the throw is what puts the mutation on
    /// the drain's failure counter instead of half-applying it.
    @Test("a patch that breaks the fat floor is refused, and nothing is written")
    func invalidPatchIsRefused() async throws {
        let store = try store()
        let before = store.goals
        let patch: MutationPayload.TargetsPatch = try Wire.decode(#"{"fatMinG": 10}"#)

        await #expect(throws: (any Error).self) {
            try await applier(store).applyTargets(patch, mutationId: "01MUTATION")
        }
        #expect(store.goals.targets.fatMinG == before.targets.fatMinG)
        #expect(store.goals.version == before.version)
    }

    @Test("a logged meal becomes one diary row per item")
    func loggedMealInsertsRows() async throws {
        let store = try store()
        let date = CalendarDate.literal("2026-11-03")
        let payload: MutationPayload.LoggedMealPayload = try Wire.decode(#"""
        {
          "date": "2026-11-03",
          "meal": "lunch",
          "items": [
            {"foodItemId": null, "name": "Chicken breast", "grams": 200,
             "kcal": 330, "proteinG": 62, "fatG": 7, "carbsG": 0},
            {"foodItemId": null, "name": "Rice", "grams": 150,
             "kcal": 195, "proteinG": 4, "fatG": 0.5, "carbsG": 43}
          ]
        }
        """#)
        let meal = LoggedMeal(id: "01MUTATION", slot: .lunch,
                              loggedAt: Timestamp.literal("2026-11-03T13:00:00-05:00"))

        try await applier(store).recordLoggedMeal(meal, payload: payload,
                                                  mutationId: "01MUTATION")

        let rows = store.mealLogs(on: date)
        #expect(rows.count == 2)
        #expect(rows.map(\.foodName).sorted() == ["Chicken breast", "Rice"])
    }

    /// `CheckIn.date` is `@Attribute(.unique)`, so a second insert for the same day would
    /// fail rather than update. The applier upserts for that reason.
    @Test("a second check-in for the same day replaces the first")
    func checkInUpserts() async throws {
        let store = try store()
        let date = CalendarDate.literal("2026-11-03")
        let applier = applier(store)

        let first: MutationPayload.CheckInPayload = try Wire.decode(
            Wire.checkIn(energy: 2, quads: "none"))
        let second: MutationPayload.CheckInPayload = try Wire.decode(
            Wire.checkIn(energy: 5, quads: "sore"))

        try await applier.applyCheckIn(first, mutationId: "01FIRST")
        try await applier.applyCheckIn(second, mutationId: "01SECOND")

        let stored = try #require(store.checkIn(on: date))
        #expect(stored.energy == 5)
        #expect(stored.soreness.quads == .sore)
    }

    @Test("set_staples replaces the staples and leaves other foods alone")
    func staplesAreReplaced() async throws {
        let store = try store()
        store.context.insert(FoodItem(dto: FoodItemDTO(
            id: "off_oats", name: "Oats", kcalPer100g: 380, proteinPer100g: 13,
            fatPer100g: 7, carbsPer100g: 67, source: .off)))
        try store.context.save()

        let replacement = FoodItemDTO(id: "staple_eggs", name: "Eggs", kcalPer100g: 143,
                                      proteinPer100g: 13, fatPer100g: 10,
                                      carbsPer100g: 1, source: .staple)
        try await applier(store).applyStaples([replacement], mutationId: "01MUTATION")

        let stored = try store.context.fetch(FetchDescriptor<FoodItem>())
        #expect(stored.filter { $0.source == .staple }.map(\.id) == ["staple_eggs"])
        #expect(stored.contains { $0.id == "off_oats" })
    }

    /// Spec §7 defines no suggestion entity, so there is nothing local to mark answered.
    /// Acknowledging it must still succeed, or the Worker redelivers it forever.
    @Test("accepting a suggestion succeeds with nothing local to change")
    func suggestionIsAcknowledged() async throws {
        let store = try store()
        try await applier(store).applySuggestion("sug_1", mutationId: "01MUTATION")
    }
}

/// Payloads built from the wire shape rather than from a memberwise initialiser.
///
/// `MutationPayload`'s structs are `Codable` with no public initialiser, which is the
/// right surface: they only ever come off `GET /v1/mutations`. Decoding the JSON the
/// Worker would send is both the only route in and a better test — a payload whose shape
/// has drifted from `docs/EXPORT_SCHEMA.md` §3 fails here rather than applying half of it.
enum Wire {
    static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func checkIn(energy: Int, quads: String) -> String {
        """
        {"date": "2026-11-03", "energy": \(energy),
         "soreness": {"chest": "none", "back": "none", "shoulders": "none",
                      "arms": "none", "quads": "\(quads)", "hamstrings": "none",
                      "glutes": "none", "core": "none"}}
        """
    }
}

/// Fixed instants the applier is given, so a stored `updatedAt` can be asserted.
enum HealthDates {
    static let fixedNow = Timestamp.literal("2026-11-03T18:00:00-05:00").date
        ?? Date(timeIntervalSince1970: 0)
}

/// An export runner with no destination, which is what a test device has.
enum ExportRunnerStub {
    @MainActor
    static func unavailable(store: LocalStore) -> ExportRunner {
        ExportRunner(
            store: store,
            ledger: RollupStore(url: FileManager.default.temporaryDirectory
                .appending(path: "export-test.\(UUID().uuidString).json")),
            destination: ExportDestination(store: InMemoryBookmarkStore()))
    }
}
