import AscensionCore
import Foundation
import SwiftData

/// Everything the Eat tab needs from outside itself.
///
/// The app shell builds this: it owns the `ModelContainer` and it is the only place
/// allowed to know about `HealthBridge`, which `FeatureEat` may not import. The
/// defaults here keep the tab honest until it does — logging works and writes to the
/// store, and a row says plainly that it has not reached Apple Health.
@MainActor
public struct EatDependencies {
    public var diary: any MealDiaryStore
    public var writeBack: any NutritionWriteBack
    public var search: (any FoodSearching)?
    public var barcodes: (any BarcodeLookup)?
    public var keys: any APIKeyStore
    public var staples: [FoodItemDTO]
    public var targets: NutritionTargets

    public init(diary: any MealDiaryStore,
                writeBack: any NutritionWriteBack = UnavailableNutritionWriteBack(),
                search: (any FoodSearching)? = nil,
                barcodes: (any BarcodeLookup)? = nil,
                keys: any APIKeyStore = KeychainAPIKeyStore(),
                staples: [FoodItemDTO] = Seed.stapleFoods,
                targets: NutritionTargets = .seeded) {
        self.diary = diary
        self.writeBack = writeBack
        self.search = search
        self.barcodes = barcodes
        self.keys = keys
        self.staples = staples
        self.targets = targets
    }

    /// The live wiring, over a store the caller owns.
    public static func live(context: ModelContext,
                            writeBack: any NutritionWriteBack = UnavailableNutritionWriteBack(),
                            keys: any APIKeyStore = KeychainAPIKeyStore()) -> EatDependencies {
        let cache = FileFoodCache()
        return EatDependencies(
            diary: SwiftDataMealDiaryStore(context: context),
            writeBack: writeBack,
            search: USDAFoodSearch(keys: keys, cache: cache),
            barcodes: OpenFoodFactsLookup(cache: cache),
            keys: keys,
            staples: staples(in: context),
            targets: targets(in: context))
    }

    /// The tab standing on its own, for the shell that has not injected anything yet.
    ///
    /// It opens the app's own store; if that fails it falls back to an in-memory one,
    /// because a tab that renders and forgets is better than a tab that cannot draw.
    public static func resolved() -> EatDependencies {
        guard let container = try? ModelContainer(for: AscensionSchema.schema) else {
            return EatDependencies(diary: InMemoryMealDiaryStore())
        }
        let context = ModelContext(container)
        try? Seed.install(into: context)
        return live(context: context)
    }

    /// Staples in the order the spec lists them — breakfast, the two chicken plates,
    /// the drink — because a store fetch has no order of its own and the row the user
    /// reaches for should not move between launches.
    private static func staples(in context: ModelContext) -> [FoodItemDTO] {
        let stored = (try? context.fetch(FetchDescriptor<FoodItem>()))?
            .filter { $0.source == .staple }
            .map(\.dto) ?? []
        guard !stored.isEmpty else { return Seed.stapleFoods }
        let seeded = Seed.stapleFoods.map(\.id)
        return stored.sorted { lhs, rhs in
            let left = seeded.firstIndex(of: lhs.id) ?? seeded.count
            let right = seeded.firstIndex(of: rhs.id) ?? seeded.count
            return left == right ? lhs.name < rhs.name : left < right
        }
    }

    private static func targets(in context: ModelContext) -> NutritionTargets {
        guard let settings = (try? context.fetch(FetchDescriptor<GoalSettings>()))?.first else {
            return .seeded
        }
        return NutritionTargets(kcal: Double(settings.kcal),
                                proteinG: Double(settings.proteinG),
                                proteinFloorG: Double(settings.proteinMinG),
                                fatMinG: Double(settings.fatMinG),
                                fatMaxG: Double(settings.fatMaxG))
    }
}
