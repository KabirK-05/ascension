import AscensionCore
import Foundation
import Testing

@testable import FeatureEat

/// ASC-24's first half: a mis-entered meal comes out of the diary **and** out of Apple
/// Health, or it comes out of neither and says so.
@Suite("Diary delete and edit")
@MainActor
struct DeleteAndEditTests {

    private func model(diary: any MealDiaryStore,
                       writeBack: any NutritionWriteBack,
                       changed: (@Sendable () async -> Void)? = nil) -> EatModel {
        EatModel(dependencies: EatDependencies(diary: diary, writeBack: writeBack,
                                               diaryDidChange: changed ?? {}),
                 date: EatSamples.day,
                 now: { EatSamples.day.date() ?? Date() })
    }

    private func loggedEntry(_ model: EatModel) async -> DiaryEntry? {
        await model.log(Portion(food: EatSamples.chickenBreast, grams: 200))
    }

    // MARK: Delete

    @Test("a logged meal leaves both the diary and Apple Health")
    func deleteRemovesBothHalves() async throws {
        let health = RecordingWriteBack()
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        #expect(await subject.delete(entry))
        #expect(subject.entries.isEmpty)
        #expect(health.removed == [entry.id])
        #expect(subject.mutationFailure == nil)
    }

    @Test("the id removed from Health is the id that was written to it")
    func removesUnderTheWrittenIdentity() async throws {
        let health = RecordingWriteBack()
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        _ = await subject.delete(entry)
        #expect(health.written.map(\.id) == health.removed)
    }

    @Test("a failed Health removal keeps the row rather than orphaning its samples")
    func keepsTheRowWhenHealthFails() async throws {
        let health = RecordingWriteBack(removalFailure: FoodLookupError.offline)
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        #expect(await subject.delete(entry) == false)
        #expect(subject.entries.count == 1)
        #expect(subject.mutationFailure == .healthUnreachable)
    }

    @Test("an unavailable removal is a failure, not a silent local delete")
    func unavailableRemovalKeepsTheRow() async throws {
        let health = RecordingWriteBack(removal: .unavailable)
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        #expect(await subject.delete(entry) == false)
        #expect(subject.entries.count == 1)
        #expect(subject.mutationFailure == .healthUnreachable)
    }

    @Test("a partial removal is a complete one: a refused scope was never written")
    func partialRemovalSucceeds() async throws {
        let health = RecordingWriteBack(outcome: .partial, removal: .partial)
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        #expect(await subject.delete(entry))
        #expect(subject.entries.isEmpty)
    }

    @Test("a row that never reached Health deletes with no write-back at all")
    func deletesWithoutAWriteBack() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(),
                            writeBack: UnavailableNutritionWriteBack())
        let entry = try #require(await loggedEntry(subject))
        #expect(entry.healthWrite == .notWritten)

        #expect(await subject.delete(entry))
        #expect(subject.entries.isEmpty)
    }

    @Test("a write-back that only knows how to add cannot drop a written row")
    func addOnlyWriteBackRefusesToOrphan() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: AddOnlyWriteBack())
        let entry = try #require(await loggedEntry(subject))
        #expect(entry.healthWrite == .written)

        #expect(await subject.delete(entry) == false)
        #expect(subject.entries.count == 1)
    }

    @Test("a store that refuses the delete leaves the row saying it is out of Health")
    func storeFailureIsReportedHonestly() async throws {
        let diary = BrittleDiaryStore()
        let subject = model(diary: diary, writeBack: RecordingWriteBack())
        let entry = try #require(await loggedEntry(subject))
        diary.failsDelete = true

        #expect(await subject.delete(entry) == false)
        #expect(subject.mutationFailure == .storeFailed)
        #expect(subject.entries.first?.healthWrite == .notWritten)
    }

    @Test("deleting tells the shell, so Today and the rollup catch up")
    func deleteNotifiesTheShell() async throws {
        let counter = Counter()
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: RecordingWriteBack(),
                            changed: { await counter.bump() })
        let entry = try #require(await loggedEntry(subject))
        let afterLog = await counter.value

        _ = await subject.delete(entry)
        #expect(await counter.value == afterLog + 1)
    }

    @Test("the day's totals drop by what was deleted")
    func totalsFollowTheDelete() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: RecordingWriteBack())
        let entry = try #require(await loggedEntry(subject))
        #expect(subject.totals.eaten.proteinG > 0)

        _ = await subject.delete(entry)
        #expect(subject.totals.eaten.proteinG == 0)
        #expect(subject.totals.eaten.kcal == 0)
    }

    // MARK: Edit

    @Test("an edit round-trips: same row, new portion, new macros")
    func editRoundTrips() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: RecordingWriteBack())
        let entry = try #require(await loggedEntry(subject))

        #expect(await subject.update(entry, to: Portion(food: EatSamples.chickenBreast,
                                                        grams: 100)))
        let edited = try #require(subject.entries.first)
        #expect(subject.entries.count == 1)
        #expect(edited.id == entry.id)
        #expect(edited.grams == 100)
        #expect(edited.macros.proteinG == 31)
    }

    @Test("an edit removes the old samples before writing the new ones")
    func editRemovesBeforeWriting() async throws {
        let health = RecordingWriteBack()
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        _ = await subject.update(entry, to: Portion(food: EatSamples.chickenBreast, grams: 100))
        #expect(health.removed == [entry.id])
        // Two writes under one id: the original and the edit. Apple Health is left
        // holding only the second, because the first was taken out in between.
        #expect(health.written.count == 2)
        #expect(health.written.allSatisfy { $0.id == entry.id })
        #expect(health.written.last?.proteinG == 31)
    }

    @Test("an edit can move a meal to another slot")
    func editMovesTheMeal() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: RecordingWriteBack())
        let entry = try #require(await loggedEntry(subject))

        _ = await subject.update(entry, to: Portion(food: EatSamples.chickenBreast, grams: 200),
                                 meal: .dinner)
        #expect(subject.entries.first?.meal == .dinner)
        #expect(subject.meals.map(\.meal) == [.dinner])
    }

    @Test("an edit Apple Health refuses changes nothing")
    func editAbortsOnHealthFailure() async throws {
        let health = RecordingWriteBack(removal: .unavailable)
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: health)
        let entry = try #require(await loggedEntry(subject))

        #expect(await subject.update(entry, to: Portion(food: EatSamples.chickenBreast,
                                                        grams: 100)) == false)
        #expect(subject.entries.first?.grams == 200)
        #expect(subject.mutationFailure == .healthUnreachable)
    }

    @Test("an edit the store refuses leaves the row saying it is out of Health")
    func editReportsAStoreFailure() async throws {
        let diary = BrittleDiaryStore()
        let subject = model(diary: diary, writeBack: RecordingWriteBack())
        let entry = try #require(await loggedEntry(subject))
        diary.failsUpdate = true

        #expect(await subject.update(entry, to: Portion(food: EatSamples.chickenBreast,
                                                        grams: 100)) == false)
        #expect(subject.mutationFailure == .storeFailed)
        #expect(subject.entries.first?.healthWrite == .notWritten)
    }

    @Test("the day's totals follow the edit")
    func totalsFollowTheEdit() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: RecordingWriteBack())
        let entry = try #require(await loggedEntry(subject))

        _ = await subject.update(entry, to: Portion(food: EatSamples.chickenBreast, grams: 100))
        #expect(subject.totals.eaten.proteinG == 31)
    }

    // MARK: The state a delete depends on

    @Test("a reload does not forget that a row reached Apple Health")
    func reloadKeepsTheHealthState() async throws {
        let subject = model(diary: InMemoryMealDiaryStore(), writeBack: RecordingWriteBack())
        _ = try #require(await loggedEntry(subject))

        subject.load()
        #expect(subject.entries.first?.healthWrite == .written)
    }
}

/// Counts callbacks across the actor hop the notification makes.
actor Counter {
    private(set) var value = 0

    func bump() { value += 1 }
}
