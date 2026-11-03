import DesignSystem
import SwiftUI

/// The Sunday review (spec §F7).
///
/// The numbers are read straight from ``WeeklyReviewFacts`` and are never generated. Only
/// the win and the focus are written — on device when the `foundationModels` flag is on
/// and the model is available, from templates otherwise — and both are measurements with
/// units, because §1.2 bans motivational copy here as firmly as anywhere else.
struct WeeklyReviewCard: View {
    let panel: ReviewPanel

    var body: some View {
        StatCard("Week") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                ForEach(panel.rows) { row in
                    ValueRow(row.label, value: row.value, unit: row.unit,
                             spokenValue: row.spokenValue)
                }
                if let text = panel.text {
                    VStack(alignment: .leading, spacing: Spacing.snug) {
                        line(text.win, tint: Palette.primaryText)
                        line(text.focus, tint: Palette.secondaryText)
                    }
                }
            }
        }
    }

    /// The win and the focus, told apart by contrast alone.
    ///
    /// There are no icons here. An arrow beside "down 0.12 kg/week" either repeats the
    /// word or contradicts it, and §2.3 reserves SF Symbols for actions and for status
    /// that has no words — this status is already words.
    private func line(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Typography.label)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
