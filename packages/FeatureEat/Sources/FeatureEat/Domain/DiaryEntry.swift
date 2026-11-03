import AscensionCore
import Foundation

/// Whether a logged meal reached Apple Health.
///
/// Spec §F3 makes the write-back the point of logging — the data has to outlive the
/// app — so a meal that did not land is worth a status marker on its row. Four cases,
/// because "some of it landed" is a real outcome: HealthKit authorisation is per type,
/// and a user who allowed protein and refused fat gets a partial write.
public enum HealthWriteState: Hashable, Sendable {
    case notWritten
    case written
    case partial
    case failed
}

/// One row of the day's diary: a portion, when it was eaten, and where it stands with
/// Apple Health.
///
/// A value type rather than the `MealLog` model so the screen, the previews and the
/// tests all share one shape and none of them need a store.
public struct DiaryEntry: Hashable, Sendable, Identifiable {
    public let id: String
    public let date: CalendarDate
    public let meal: MealKind
    /// The `FoodItem` this came from, or `nil` for a one-off manual entry — the same
    /// distinction the export's `meals[]` rows make.
    public let foodId: String?
    public let foodName: String
    public let grams: Double
    public let macros: Macros
    public let loggedAt: Date
    public var healthWrite: HealthWriteState

    public init(id: String = UUID().uuidString, date: CalendarDate, meal: MealKind,
                foodId: String? = nil, foodName: String, grams: Double, macros: Macros,
                loggedAt: Date, healthWrite: HealthWriteState = .notWritten) {
        self.id = id
        self.date = date
        self.meal = meal
        self.foodId = foodId
        self.foodName = foodName
        self.grams = grams
        self.macros = macros
        self.loggedAt = loggedAt
        self.healthWrite = healthWrite
    }

    public init(id: String = UUID().uuidString, date: CalendarDate, meal: MealKind,
                portion: Portion, loggedAt: Date,
                healthWrite: HealthWriteState = .notWritten) {
        self.init(id: id, date: date, meal: meal, foodId: portion.food.id,
                  foodName: portion.food.name, grams: portion.grams,
                  macros: portion.macros, loggedAt: loggedAt, healthWrite: healthWrite)
    }
}

extension MealKind {
    /// The order a day is eaten in, which is the order the diary lists.
    public var diaryOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }

    public var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }

    /// The meal a log at this hour most likely belongs to.
    ///
    /// Guessing removes a picker from the one-tap path (design rule 2.1); the portion
    /// sheet still lets the guess be corrected, so a wrong guess costs one tap.
    public static func forHour(_ hour: Int) -> MealKind {
        switch hour {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    public static func current(_ now: Date, calendar: Calendar = .current) -> MealKind {
        forHour(calendar.component(.hour, from: now))
    }
}
