import AppIntents
import AscensionCore
import Foundation
import SystemSurfaces

/// The four voice actions spec §F8 names, and no others.
///
/// All four run in the app's own process with no UI: `openAppWhenRun` is left false, so
/// "log my omelette" from the Watch, the Lock Screen or Siri writes to Apple Health
/// without a screen ever appearing. That is the point — §F8 calls voice logging a core
/// habit feature, and a habit that takes a launch and four taps is not one.

/// "What's my readiness?"
struct ReadinessQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "Readiness"
    static let description = IntentDescription("Today's readiness score and verdict.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let readiness = await (try IntentActions.resolve()).readiness() else {
            return .result(dialog: "Nothing scored yet today.")
        }
        let verdict = SurfaceText.verdict(readiness.verdict)
        return .result(dialog: "Readiness \(readiness.score). \(verdict).")
    }
}

/// "Log water". Defaults to a glass, because the common case should take no parameter.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription("Add water to Apple Health.")
    static let openAppWhenRun = false

    /// Millilitres — spec §8: kg, kcal and grams everywhere, and water in ml.
    @Parameter(title: "Millilitres", default: 250, inclusiveRange: (50, 2000))
    var millilitres: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentActions.resolve().logWater(millilitres: Double(millilitres))
        return .result(dialog: "\(millilitres) ml logged.")
    }
}

/// "Log my omelette" — one of the staples, at its own serving unless a weight is given.
struct LogStapleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a staple"
    static let description = IntentDescription("Log one of your staple foods.")
    static let openAppWhenRun = false

    @Parameter(title: "Food")
    var food: StapleEntity

    @Parameter(title: "Grams")
    var grams: Int?

    @Parameter(title: "Meal", default: .snack)
    var meal: MealSlot

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let actions = try IntentActions.resolve()
        let macros = try await actions.log(foodId: food.id,
                                           grams: grams.map(Double.init),
                                           meal: meal.kind)
        let logged = SurfaceText.grams(macros.proteinG)
        let remaining = SurfaceText.grams(actions.proteinRemaining())
        return .result(dialog: "\(logged) protein logged. \(remaining) to go.")
    }
}

/// "Log top set" — the one set per exercise per day the program progresses on.
struct LogTopSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log top set"
    static let description = IntentDescription("Record the day's top set for an exercise.")
    static let openAppWhenRun = false

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Weight")
    var weightKg: Double

    @Parameter(title: "Reps", inclusiveRange: (1, 50))
    var reps: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await (try IntentActions.resolve()).logTopSet(exerciseId: exercise.id,
                                                      weightKg: weightKg, reps: reps)
        let weight = weightKg.formatted(.number.precision(.fractionLength(0...1)))
        return .result(dialog: "\(exercise.name) \(weight) kg by \(reps) logged.")
    }
}

/// The meal of the day a voice log lands in. A closed set, mirroring `MealKind` without
/// making `AscensionCore`'s own enum conform to `AppEnum` — that package has no reason to
/// know App Intents exists.
enum MealSlot: String, AppEnum {
    case breakfast, lunch, dinner, snack

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")
    static let caseDisplayRepresentations: [MealSlot: DisplayRepresentation] = [
        .breakfast: "Breakfast", .lunch: "Lunch", .dinner: "Dinner", .snack: "Snack"
    ]

    var kind: MealKind {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return .snack
        }
    }
}

/// The phrases Siri and Shortcuts offer without the user wiring anything up.
struct AscensionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ReadinessQueryIntent(),
                    phrases: ["What's my readiness in \(.applicationName)",
                              "\(.applicationName) readiness"],
                    shortTitle: "Readiness",
                    systemImageName: "bolt.heart")
        AppShortcut(intent: LogWaterIntent(),
                    phrases: ["Log water in \(.applicationName)",
                              "\(.applicationName) log water"],
                    shortTitle: "Water",
                    systemImageName: "drop")
        AppShortcut(intent: LogStapleIntent(),
                    phrases: ["Log a meal in \(.applicationName)",
                              "\(.applicationName) log food"],
                    shortTitle: "Meal",
                    systemImageName: "fork.knife")
        AppShortcut(intent: LogTopSetIntent(),
                    phrases: ["Log a top set in \(.applicationName)",
                              "\(.applicationName) log top set"],
                    shortTitle: "Top set",
                    systemImageName: "figure.strengthtraining.traditional")
    }
}
