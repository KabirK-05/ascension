import DesignSystem
import SwiftUI

/// The weekly calorie auto-adjust, surfaced for one tap (spec §F6).
///
/// The card exists only while the engine proposes something, and tapping accept is the
/// only way a target moves: spec §F6 is explicit that nothing changes silently. The
/// engine's `reason` is printed because it is a measurement with units — "losing 0.95
/// kg/week" — and not an explanation of the card it sits in (§1.1).
struct SuggestionCard: View {
    let panel: SuggestionPanel
    let state: TrendsModel.AcceptState
    let accept: (String) -> Void

    var body: some View {
        StatCard("Calories") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                ValueRow("Suggested", value: "\(panel.suggestedKcal)", unit: "kcal",
                         emphasis: .hero,
                         spokenValue: "\(panel.suggestedKcal) kilocalories, "
                             + "currently \(panel.currentKcal)")
                Text(panel.reason)
                    .font(Typography.detail)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                control
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch state {
        case .accepting:
            ProgressView().controlSize(.small)
        case .accepted:
            Label("Accepted", systemImage: "checkmark")
                .font(Typography.label)
                .foregroundStyle(Palette.accent)
        case .idle, .failed:
            Button(state == .failed ? "Retry" : "Accept") { accept(panel.id) }
                .font(Typography.label)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .accessibilityLabel("Accept \(panel.suggestedKcal) kilocalories")
        }
    }
}
