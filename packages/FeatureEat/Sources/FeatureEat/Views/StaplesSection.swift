import AscensionCore
import DesignSystem
import SwiftUI

/// The primary logging path (spec §F3): the four staples, one tap each.
///
/// It sits above the diary and stays there whether the day is empty or full, which is
/// what makes the empty state a control rather than a sentence (design rule 1.4).
struct StaplesSection: View {
    let staples: [FoodItemDTO]
    let log: (FoodItemDTO) -> Void

    var body: some View {
        Section("Staples") {
            ForEach(staples) { staple in
                Button {
                    log(staple)
                } label: {
                    FoodRow(name: staple.name,
                            portion: staple.servingName,
                            proteinG: staple.servingMacros?.proteinG ?? 0)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Logs this")
            }
        }
    }
}
