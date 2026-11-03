import AscensionCore
import AscensionEngines
import ExportKit
import FeatureTrain
import Foundation
import SwiftData
import SyncClient

/// Everything the shell reads out of SwiftData, in one place.
///
/// `@MainActor` on purpose. `ModelContext` is not `Sendable`, and the alternative —
/// a second context per background task — buys nothing here: this is a single-user app
/// whose heaviest read is a few hundred rows, and a background task that hops to the main
/// actor for a few milliseconds is cheaper to reason about than two contexts that can
/// disagree. Every caller is already async.
@MainActor
final class LocalStore {
    let container: ModelContainer
    let context: ModelContext
    private let flags: FlagsStore

    init(container: ModelContainer, flags: FlagsStore = FlagsStore()) {
        self.container = container
        self.context = ModelContext(container)
        self.flags = flags
    }

    // MARK: - Documents

    /// The targets the user is actually on, falling back to the seed when the store is
    /// empty — which is the state between a first launch and ``installSeed()``.
    var goals: GoalSettingsDocument {
        let stored = try? context.fetch(FetchDescriptor<GoalSettings>())
        return stored?.first?.document ?? Seed.goalSettings
    }

    var program: ProgramDocument {
        let stored = try? context.fetch(FetchDescriptor<Program>())
        let active = stored?.first { $0.isActive } ?? stored?.first
        return active?.document ?? Seed.program
    }

    var documents: ExportDocuments {
        ExportDocuments(goalSettings: goals, program: program, flags: flags.document)
    }

    /// Installs the seed once. Idempotent in `AscensionCore`: it inserts nothing when goal
    /// settings already exist, so a relaunch never duplicates or overwrites an edit.
    @discardableResult
    func installSeed() -> Bool {
        do {
            try Seed.install(into: context)
            return true
        } catch {
            return false
        }
    }

    // MARK: - The device half of a rollup

    /// Meals, top sets, the check-in and the stored readiness for one day.
    ///
    /// `LoggedMeal.id` is derived from the row's position in a sorted day rather than read
    /// off the model, because `MealLog` (spec §7) carries no row id — the same reason
    /// `SwiftDataMealDiaryStore` keeps its own. The ids are only ever used to total the
    /// day, so a derived one is enough; the sort keeps it stable between two refreshes of
    /// the same day.
    func deviceDay(on date: CalendarDate,
                   planned: SessionKind?,
                   sessionDone: Bool,
                   trends: TrendOverlay,
                   clock: DayClock) -> DeviceDay {
        DeviceDay(meals: loggedMeals(on: date, clock: clock),
                  sessionPlanned: planned,
                  sessionDone: sessionDone,
                  topSets: topSetLogs(on: date).map(\.topSet),
                  checkIn: checkIn(on: date),
                  readiness: readiness(on: date),
                  trends: trends)
    }

    func loggedMeals(on date: CalendarDate, clock: DayClock) -> [LoggedMeal] {
        mealLogs(on: date).enumerated().map { index, log in
            LoggedMeal(id: "\(date.rawValue)/\(log.meal.rawValue)/\(index)",
                       slot: log.meal,
                       loggedAt: Timestamp(clock.middayOf(date), timeZone: clock.timeZone),
                       kcal: log.kcal,
                       proteinG: log.proteinG,
                       fatG: log.fatG,
                       carbsG: log.carbsG)
        }
    }

    /// Deterministically ordered: meal through the day, then the fields a row is made of.
    /// A `FetchDescriptor` has no inherent order, and two refreshes of one day must not
    /// shuffle the rows and look like a change.
    func mealLogs(on date: CalendarDate) -> [MealLog] {
        let day = date.rawValue
        let descriptor = FetchDescriptor<MealLog>(predicate: #Predicate { $0.date == day })
        return (try? context.fetch(descriptor))?.sorted { lhs, rhs in
            if lhs.meal != rhs.meal {
                return Self.order(of: lhs.meal) < Self.order(of: rhs.meal)
            }
            if lhs.foodName != rhs.foodName { return lhs.foodName < rhs.foodName }
            if lhs.grams != rhs.grams { return lhs.grams < rhs.grams }
            return lhs.kcal < rhs.kcal
        } ?? []
    }

    /// Meals sort through the day. `FeatureEat` and `ExportKit` each have their own copy
    /// of this order, neither reachable from here — one is a feature the shell must not
    /// lean on for arithmetic, the other is internal to its package.
    static func order(of meal: MealKind) -> Int {
        switch meal {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }

    func topSetLogs(on date: CalendarDate) -> [TopSetLog] {
        let day = date.rawValue
        let descriptor = FetchDescriptor<TopSetLog>(predicate: #Predicate { $0.date == day })
        return (try? context.fetch(descriptor))?.sorted { $0.exerciseId < $1.exerciseId } ?? []
    }

    func checkIn(on date: CalendarDate) -> CheckInRollup? {
        let day = date.rawValue
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.date == day })
        return (try? context.fetch(descriptor))?.first?.rollup
    }

    func readiness(on date: CalendarDate) -> ReadinessRollup? {
        let day = date.rawValue
        let descriptor = FetchDescriptor<ReadinessSnapshot>(
            predicate: #Predicate { $0.date == day })
        return (try? context.fetch(descriptor))?.first?.rollup
    }

    // MARK: - Train

    func loggedTopSets(in dates: [CalendarDate]) -> [LoggedTopSet] {
        dates.flatMap { date in
            topSetLogs(on: date).map {
                LoggedTopSet(date: date, exerciseId: $0.exerciseId, weightKg: $0.weightKg,
                             reps: $0.reps, sessionKind: $0.sessionType)
            }
        }
    }

    func save(topSets: [LoggedTopSet]) {
        for logged in topSets {
            let day = logged.date.rawValue
            let exerciseId = logged.exerciseId
            let existing = FetchDescriptor<TopSetLog>(
                predicate: #Predicate { $0.date == day && $0.exerciseId == exerciseId })
            for stale in (try? context.fetch(existing)) ?? [] {
                context.delete(stale)
            }
            context.insert(TopSetLog(date: logged.date, exerciseId: logged.exerciseId,
                                     weightKg: logged.weightKg, reps: logged.reps,
                                     sessionType: logged.sessionKind))
        }
        try? context.save()
    }

    // MARK: - Export

    /// `exerciseId` → display name, for the journal. The library is ASC-8's; an id with no
    /// row falls back inside `ExportKit` to a readable form of itself.
    var exerciseNames: [String: String] {
        let stored = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return Dictionary(stored.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    func mealEntries(in dates: [CalendarDate]) -> [MealEntry] {
        dates.flatMap { date in
            mealLogs(on: date).map { log in
                MealEntry(date: date, meal: log.meal, foodItemId: log.foodItem?.id,
                          name: log.foodName, grams: log.grams, kcal: log.kcal,
                          proteinG: log.proteinG, fatG: log.fatG, carbsG: log.carbsG)
            }
        }
    }
}
