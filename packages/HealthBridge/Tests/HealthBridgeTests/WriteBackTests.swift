import Foundation
import Testing

@testable import HealthBridge

@Suite("write-back: nutrition, water and manual body measurements")
struct WriteBackTests {
    private let meal = NutritionEntry(
        id: "01JC4PZ8KQ0000000000000001",
        consumedAt: Fixture.instant(hour: 13),
        energyKcal: 650, proteinG: 55, carbsG: 68, fatG: 14)

    @Test("a meal writes one sample per macro, in the narrow §6 scope")
    func mealWritesEachMacro() async throws {
        let store = FakeHealthStore()
        let receipt = try await HealthWriter(store: store).write(meal)

        #expect(receipt.savedMetrics == [.dietaryEnergy, .dietaryProtein,
                                         .dietaryCarbohydrates, .dietaryFat])
        #expect(receipt.didSaveEverything)
        #expect(store.saved.count == 4)
    }

    @Test("retrying the same mutation does not double-log the meal")
    func retryIsIdempotent() async throws {
        let store = FakeHealthStore()
        let writer = HealthWriter(store: store)

        try await writer.write(meal)
        try await writer.write(meal)
        try await writer.write(meal)

        // Four samples, not twelve: every sample carries the same sync identifier, so
        // HealthKit replaces rather than appends.
        #expect(store.saved.count == 4)
        let identifiers = Set(store.saved.map(\.syncIdentifier))
        #expect(identifiers.count == 4)
    }

    @Test("the sync identifier is derived from the entry id, not from the attempt")
    func syncIdentifiersAreDeterministic() {
        let first = HealthSampleFactory.samples(for: meal).saved
        let second = HealthSampleFactory.samples(for: meal).saved
        #expect(first == second)
        #expect(first.allSatisfy { $0.syncIdentifier.contains(meal.id) })
        #expect(first.first?.syncIdentifier
            == "com.kabirkumar.ascension.v1.dietaryCarbohydrates.\(meal.id)")
    }

    @Test("an edited meal replaces the earlier version")
    func editedMealBumpsTheVersion() async throws {
        let store = FakeHealthStore()
        let writer = HealthWriter(store: store)
        try await writer.write(meal)

        var corrected = meal
        corrected.proteinG = 61
        corrected.revision = 2
        try await writer.write(corrected)

        #expect(store.saved.count == 4)
        let protein = store.saved.first { $0.metric == .dietaryProtein }
        #expect(protein?.value == 61)
        #expect(protein?.syncVersion == 2)
    }

    @Test("a refused scope is reported, and the fields that were allowed still land")
    func partialAuthorizationWritesWhatItCan() async throws {
        let store = FakeHealthStore()
        store.update { $0.writeStatuses[.dietaryFat] = .denied }
        let receipt = try await HealthWriter(store: store).write(meal)

        #expect(receipt.savedMetrics == [.dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates])
        #expect(receipt.skipped[.dietaryFat] == .notAuthorized(.denied))
        #expect(receipt.didSaveEverything == false)
        #expect(store.saved.contains { $0.metric == .dietaryFat } == false)
    }

    @Test("a scope never asked about is not treated as consent")
    func undeterminedIsNotGranted() async throws {
        let store = FakeHealthStore()
        store.update { $0.writeStatuses[.dietaryProtein] = .notDetermined }
        let receipt = try await HealthWriter(store: store).write(meal)
        #expect(receipt.skipped[.dietaryProtein] == .notAuthorized(.notDetermined))
    }

    @Test("a nonsense value is refused rather than written")
    func invalidValuesAreRefused() async throws {
        let store = FakeHealthStore()
        let entry = NutritionEntry(id: "bad", consumedAt: Fixture.instant(hour: 13),
                                   energyKcal: -10, proteinG: .nan, carbsG: 0)
        let receipt = try await HealthWriter(store: store).write(entry)

        #expect(receipt.skipped[.dietaryEnergy] == .invalidValue(-10))
        #expect(receipt.skipped.keys.contains(.dietaryProtein))
        // Zero is a measurement, not a mistake: a zero-calorie drink is a real log.
        #expect(receipt.savedMetrics == [.dietaryCarbohydrates])
    }

    @Test("water logs on its own")
    func waterLogsAlone() async throws {
        let store = FakeHealthStore()
        let receipt = try await HealthWriter(store: store)
            .writeWater(millilitres: 400, at: Fixture.instant(hour: 10), entryId: "water-1")

        #expect(receipt.savedMetrics == [.dietaryWater])
        #expect(store.saved.first?.value == 400)
    }

    @Test("a manual weight and waist entry writes both")
    func bodyMeasurementsWrite() async throws {
        let store = FakeHealthStore()
        let entry = BodyMeasurementEntry(id: "weigh-1", measuredAt: Fixture.instant(hour: 7),
                                         weightKg: 73.6, waistCm: 84)
        let receipt = try await HealthWriter(store: store).write(entry)
        #expect(receipt.savedMetrics == [.bodyMass, .waistCircumference])
    }

    @Test("writing without HealthKit fails loudly instead of silently dropping a meal")
    func unavailableStoreThrows() async {
        let store = FakeHealthStore(config: .init(available: false))
        await #expect(throws: HealthStoreError.healthDataUnavailable) {
            try await HealthWriter(store: store).write(meal)
        }
    }

    @Test("the write scope is exactly what spec §6 permits")
    func writeScopeIsNarrow() {
        #expect(HealthScopes.write.count == 7)
        #expect(HealthScopes.write.contains(.bodyMass))
        #expect(HealthScopes.write.contains(.waistCircumference))
        #expect(HealthWriteMetric.allCases.allSatisfy { $0.unitLabel.isEmpty == false })
    }
}
