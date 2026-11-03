import DesignSystem
import SwiftUI

/// Calories and protein against their targets, as the two rings Apple Fitness pairs on
/// its summary. Tapping goes to Eat — that is the disclosure mechanism (§5.3), and the
/// rings name themselves, so the card carries no label of its own.
///
/// The destination arrives as a closure. `FeatureToday` imports no other feature.
struct NutritionCard: View {
    let panel: NutritionPanel
    let openEat: (() -> Void)?

    var body: some View {
        if let openEat {
            Button(action: openEat) { card }
                .buttonStyle(.plain)
                .accessibilityHint("Eat")
        } else {
            card
        }
    }

    private var card: some View {
        StatCard {
            HStack(spacing: Spacing.section) {
                MetricRing("Calories", value: panel.kcal, goal: panel.kcalTarget)
                MetricRing("Protein", value: panel.proteinGrams,
                           goal: panel.proteinTargetGrams, unit: "g")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The day's measurements, in the order spec §F1 asks for them: sleep and how steady
/// bedtime has been, then steps, energy and exercise.
///
/// No card label. Each row is a noun and a number, so a heading above them would only
/// repeat what they already say (§2.1).
struct MeasurementsCard: View {
    let rows: [MeasurementRow]

    var body: some View {
        StatCard {
            VStack(spacing: Spacing.regular) {
                ForEach(rows) { row in
                    ValueRow(row.label,
                             value: row.value,
                             unit: row.unit,
                             progress: row.progress,
                             spokenValue: row.spokenValue)
                }
            }
        }
    }
}
