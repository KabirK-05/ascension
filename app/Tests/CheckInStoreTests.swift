import AscensionCore
import FeatureToday
import Foundation
import SwiftData
import Testing

@testable import Ascension

/// The gap this ticket closed: `LocalStore.upsertCheckIn` existed for Muse's `log_checkin`,
/// but nothing in the shell passed a `CheckInStore` to Today, so the user's own check-in
/// never reached SwiftData and was lost on relaunch.
@Suite("the check-in reaches the store")
@MainActor
struct CheckInStoreTests {
    private let date = CalendarDate(rawValue: "2026-11-03") ?? CalendarDate.distantPast

    private func store() throws -> LocalStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AscensionSchema.schema,
                                           configurations: configuration)
        return LocalStore(container: container)
    }

    private func saved(in store: LocalStore) throws -> [CheckIn] {
        try store.context.fetch(FetchDescriptor<CheckIn>())
    }

    @Test("a tapped check-in is persisted, not held in memory")
    func savesToSwiftData() async throws {
        let store = try store()
        let rollup = CheckInRollup(energy: 4,
                                   soreness: Soreness(quads: .sore, hamstrings: .mild))

        try await LocalCheckInStore(store: store).save(rollup, on: date)

        let rows = try saved(in: store)
        #expect(rows.count == 1)
        #expect(rows.first?.date == date.rawValue)
        #expect(rows.first?.energy == 4)
        #expect(rows.first?.soreness.quads == .sore)
        #expect(rows.first?.soreness.hamstrings == .mild)
    }

    /// ASC-14's reopen re-saves the same day. `CheckIn.date` is `@Attribute(.unique)`, so a
    /// second insert would fail rather than update — the upsert is what makes reopening work.
    @Test("reopening the same day replaces its row instead of adding a second")
    func reopenUpserts() async throws {
        let store = try store()
        let subject = LocalCheckInStore(store: store)

        try await subject.save(CheckInRollup(energy: 2, soreness: Soreness(quads: .sore)),
                               on: date)
        try await subject.save(CheckInRollup(energy: 5, soreness: Soreness()), on: date)

        let rows = try saved(in: store)
        #expect(rows.count == 1)
        #expect(rows.first?.energy == 5)
        #expect(rows.first?.soreness.quads == SorenessLevel.none)
    }
}
