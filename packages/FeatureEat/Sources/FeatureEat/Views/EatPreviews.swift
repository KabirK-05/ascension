#if DEBUG
import AscensionCore
import DesignSystem
import SwiftUI

extension EatDependencies {
    /// A tab with a day already half eaten, for previews and for the simulator run
    /// the PR screenshots come from.
    @MainActor
    static func preview(entries: [DiaryEntry] = EatSamples.entries(),
                        key: String? = nil) -> EatDependencies {
        let keys = EphemeralAPIKeyStore(keys: key.map { [.usda: $0] } ?? [:])
        return EatDependencies(
            diary: InMemoryMealDiaryStore(entries: entries,
                                          foods: [EatSamples.chickenBreast, EatSamples.oats]),
            keys: keys,
            targets: .seeded)
    }
}

@MainActor
private func previewScreen(entries: [DiaryEntry] = EatSamples.entries()) -> some View {
    EatScreen(dependencies: .preview(entries: entries))
}

#Preview("Eat — dark") {
    previewScreen().preferredColorScheme(.dark)
}

#Preview("Eat — light") {
    previewScreen().preferredColorScheme(.light)
}

#Preview("Eat — empty day") {
    previewScreen(entries: []).preferredColorScheme(.dark)
}

#Preview("Totals — dark") {
    TotalsHeader(totals: DayTotals(entries: EatSamples.entries(), targets: .seeded))
        .padding(Spacing.screenMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
        .preferredColorScheme(.dark)
}

#Preview("Totals — light") {
    TotalsHeader(totals: DayTotals(entries: EatSamples.entries(), targets: .seeded))
        .padding(Spacing.screenMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
        .preferredColorScheme(.light)
}

#Preview("Portion — dark") {
    PortionSheet(food: EatSamples.chickenBreast, meal: .dinner) { _, _ in }
        .preferredColorScheme(.dark)
}

#Preview("Food data — light") {
    FoodDataSettingsView(keys: EphemeralAPIKeyStore())
        .preferredColorScheme(.light)
}
#endif
