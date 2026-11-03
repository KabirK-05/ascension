import AscensionCore
import DesignSystem
import SwiftUI

/// One meal of the day's diary, with the meal's own calories on its header — the
/// MyFitnessPal and Cronometer arrangement, which is where a day's calories are
/// usefully read: per meal, not per row.
struct DiarySection: View {
    let section: MealSection
    let delete: (DiaryEntry) -> Void

    var body: some View {
        Section {
            ForEach(section.entries) { entry in
                FoodRow(name: entry.foodName,
                        portion: "\(Figure.grams(entry.grams)) g",
                        proteinG: entry.macros.proteinG,
                        state: entry.healthWrite)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(entry)
                        }
                    }
            }
        } header: {
            HStack {
                Text(section.meal.title)
                Spacer()
                Text("\(Figure.whole(section.macros.kcal)) kcal")
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }
}
