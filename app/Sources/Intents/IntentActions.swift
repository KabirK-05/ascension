import AscensionCore
import FeatureTrain
import Foundation
import HealthBridge
import SystemSurfaces

/// What an App Intent is allowed to do, in one place.
///
/// Spec §F8 calls voice logging a core habit feature, so these run without opening the
/// app: the system launches the process, resolves the intent and the work happens here —
/// no screen, no `openAppWhenRun`.
///
/// Every write takes the same route a tap would: Apple Health first, then the local diary,
/// then the shared snapshot so the widgets agree. Nothing here invents a second write path.
@MainActor
struct IntentActions {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notReady
        case unknownFood

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .notReady: return "Ascension is not ready yet"
            case .unknownFood: return "That is not one of your staples"
            }
        }
    }

    let composition: AppComposition

    /// The running composition, or a failure. An intent fired before the app delegate has
    /// run has nothing to write through, and saying so beats writing nowhere.
    static func resolve() throws -> IntentActions {
        guard let composition = AppComposition.shared else { throw Failure.notReady }
        return IntentActions(composition: composition)
    }

    // MARK: - Reads

    /// Today's readiness, freshly derived rather than read off the snapshot: "what's my
    /// readiness?" asked at 6 am must not answer with last night's score.
    func readiness() async -> (score: Int, verdict: ReadinessVerdict)? {
        let report = await composition.refresher.refresh()
        guard let readiness = report.today.readiness else { return nil }
        return (readiness.score, readiness.verdict)
    }

    func staples() -> [FoodItemDTO] { composition.store.staples }

    func exercises() -> [String: String] { composition.store.exerciseNames }

    // MARK: - Writes

    /// Logs one staple at a portion, into Apple Health and the diary.
    ///
    /// The portion defaults to the staple's own serving, because "log my omelette" names a
    /// food and not a weight, and a staple without a serving falls back to 100 g — the
    /// basis every macro in the store is carried in.
    @discardableResult
    func log(foodId: String, grams: Double?, meal: MealKind) async throws -> Macros {
        guard let food = staples().first(where: { $0.id == foodId }) else {
            throw Failure.unknownFood
        }
        let portion = grams ?? food.servingGrams ?? 100
        let macros = food.macros(forGrams: portion)
        let clock = DayClock(goals: composition.store.goals)
        let now = Date()

        try await composition.writer.write(HealthBridge.NutritionEntry(
            id: UUID().uuidString, consumedAt: now,
            energyKcal: macros.kcal, proteinG: macros.proteinG,
            carbsG: macros.carbsG, fatG: macros.fatG))

        try composition.store.insertMeal(date: clock.day(of: now), meal: meal,
                                         food: food, grams: portion, macros: macros)

        await publish()
        return macros
    }

    func logWater(millilitres: Double) async throws {
        try await composition.writer.writeWater(millilitres: millilitres, at: Date(),
                                                entryId: UUID().uuidString)
        await publish()
    }

    func logTopSet(exerciseId: String, weightKg: Double, reps: Int) async {
        let clock = DayClock(goals: composition.store.goals)
        composition.store.save(topSets: [LoggedTopSet(date: clock.day(of: Date()),
                                                      exerciseId: exerciseId,
                                                      weightKg: weightKg, reps: reps)])
        await publish()
    }

    /// Protein left today, for the dialog an intent speaks back.
    func proteinRemaining() -> Double {
        composition.surfaces.read()?.proteinRemainingG ?? 0
    }

    private func publish() async {
        await SurfacePublisher(composition: composition).publish()
    }
}
