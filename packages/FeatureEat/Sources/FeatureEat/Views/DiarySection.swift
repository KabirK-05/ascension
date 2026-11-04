import AscensionCore
import DesignSystem
import SwiftUI

/// One meal of the day's diary, with the meal's own calories on its header — the
/// MyFitnessPal and Cronometer arrangement, which is where a day's calories are
/// usefully read: per meal, not per row.
///
/// Two affordances, both native and both MyFitnessPal's: swipe a row to delete it, tap
/// it to change it. Nothing on screen says so (rule 1.2 bans "Swipe to…"), because on
/// iOS a list row does not need to.
struct DiarySection: View {
    let section: MealSection
    let delete: (DiaryEntry) -> Void
    let edit: (DiaryEntry) -> Void

    var body: some View {
        Section {
            ForEach(section.entries) { entry in
                Button {
                    edit(entry)
                } label: {
                    FoodRow(name: entry.foodName,
                            portion: "\(Figure.grams(entry.grams)) g",
                            proteinG: entry.macros.proteinG,
                            state: entry.healthWrite)
                }
                .buttonStyle(.plain)
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
