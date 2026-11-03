import AscensionCore
import DesignSystem
import SwiftUI

/// The answer to the tab's one question (design rule 2.1).
///
/// The protein ring is the hero (spec §4): what is left is the gap in the ring, which
/// is why there is no second number saying so in words. Calories, fat and carbohydrate
/// sit under it as rows, in the Cronometer / MyFitnessPal order — the day's budget,
/// then the two macros that spend it.
struct TotalsHeader: View {
    let totals: DayTotals

    var body: some View {
        StatCard {
            VStack(spacing: Spacing.section) {
                MetricRing("Protein",
                           value: totals.eaten.proteinG,
                           goal: totals.targets.proteinG,
                           unit: "g",
                           size: .hero)
                    .frame(maxWidth: .infinity)

                VStack(spacing: Spacing.regular) {
                    ValueRow("Calories",
                             value: Figure.whole(totals.eaten.kcal),
                             unit: "kcal",
                             progress: totals.kcalProgress,
                             spokenValue: spoken(totals.eaten.kcal, totals.targets.kcal, "kilocalories"))
                    ValueRow("Fat",
                             value: Figure.whole(totals.eaten.fatG),
                             unit: "g",
                             progress: totals.fatProgress,
                             spokenValue: spoken(totals.eaten.fatG, totals.targets.fatMaxG, "grams"))
                    ValueRow("Carbs",
                             value: Figure.whole(totals.eaten.carbsG),
                             unit: "g",
                             progress: totals.carbsProgress,
                             spokenValue: spoken(totals.eaten.carbsG, totals.targets.carbsG, "grams"))
                }
            }
        }
    }

    /// VoiceOver reads the target too: the ring's gap is the answer on screen, and a
    /// spoken row has no gap to look at.
    private func spoken(_ value: Double, _ goal: Double, _ unit: String) -> String {
        "\(Figure.whole(value)) of \(Figure.whole(goal)) \(unit)"
    }
}
