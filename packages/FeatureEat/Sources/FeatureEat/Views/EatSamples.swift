import AscensionCore
import Foundation

/// Invented data for previews and tests. No real health data ever enters the repo.
///
/// It obeys the dietary rules it is sampling (spec §2): chicken and eggs, rice and
/// potatoes, and milk with Bournvita as the one dairy drink. A sample that broke them
/// would be a bug the previews showed off.
public enum EatSamples {
    public static let day = CalendarDate(rawValue: "2026-11-03") ?? Seed.goalSettings.programStartDate

    public static let chickenBreast = FoodItemDTO(
        id: "usda_171077", name: "Chicken breast, roasted",
        kcalPer100g: 165, proteinPer100g: 31, fatPer100g: 3.6, carbsPer100g: 0,
        source: .usda)

    public static let egg = FoodItemDTO(
        id: "usda_748967", name: "Egg, whole, cooked",
        kcalPer100g: 155, proteinPer100g: 13, fatPer100g: 11, carbsPer100g: 1.1,
        source: .usda)

    public static let rice = FoodItemDTO(
        id: "usda_168878", name: "Rice, white, cooked",
        kcalPer100g: 130, proteinPer100g: 2.7, fatPer100g: 0.3, carbsPer100g: 28,
        source: .usda)

    /// A packaged food with a barcode, as a scan would return it.
    public static let oats = FoodItemDTO(
        id: "off_5000108501000", name: "Rolled oats", brand: "Quaker",
        kcalPer100g: 372, proteinPer100g: 11.2, fatPer100g: 8.0, carbsPer100g: 60.0,
        source: .off, barcode: "5000108501000", servingGrams: 40, servingName: "40 g")

    /// One staple eaten at one hour of the day.
    struct SampleLog {
        let staple: Int
        let meal: MealKind
        let hour: Int
    }

    /// Mid-afternoon: the omelette, the chicken-and-rice plate, and a glass of milk.
    public static func entries(on date: CalendarDate = EatSamples.day) -> [DiaryEntry] {
        let staples = Seed.stapleFoods
        let plan = [SampleLog(staple: 0, meal: .breakfast, hour: 9),
                    SampleLog(staple: 1, meal: .lunch, hour: 13),
                    SampleLog(staple: 3, meal: .snack, hour: 15)]
        return plan.compactMap { log in
            guard log.staple < staples.count,
                  let portion = Portion(serving: staples[log.staple]),
                  let start = date.date() else { return nil }
            return DiaryEntry(date: date, meal: log.meal, portion: portion,
                              loggedAt: start.addingTimeInterval(Double(log.hour) * 3600),
                              healthWrite: .written)
        }
    }
}
