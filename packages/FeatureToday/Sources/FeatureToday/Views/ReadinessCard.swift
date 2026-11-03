import DesignSystem
import SwiftUI

/// The hero of Today: the score, the verdict, and the two facts behind them.
///
/// The arrangement is Oura's readiness header — the number large, a short verdict on its
/// baseline rather than a sentence beneath it — over Whoop's contributor list, which
/// reports each driver as a value instead of a paragraph. Both of those apps then print
/// a grey explanatory paragraph under the score; that is the one thing deliberately not
/// adapted (§1.1). The engine's two reasons are facts with units and stand alone.
struct ReadinessCard: View {
    let panel: ReadinessPanel

    var body: some View {
        StatCard("Readiness") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                header
                if !panel.reasons.isEmpty {
                    reasons
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
                score
                verdict
            }
            VStack(alignment: .leading, spacing: Spacing.tight) {
                score
                verdict
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness")
        .accessibilityValue("\(panel.score). \(panel.verdict.text)")
    }

    private var score: some View {
        Text(panel.score.formatted())
            .font(Typography.heroValue)
            .monospacedDigit()
            .foregroundStyle(Palette.primaryText)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.45), value: panel.score)
    }

    /// The verdict is the status, so it is the one thing on this card that carries
    /// colour (§2.4): clear, careful, or stand down.
    private var verdict: some View {
        Text(panel.verdict.text)
            .font(Typography.unit)
            .foregroundStyle(verdictColour)
    }

    private var verdictColour: Color {
        switch panel.verdict {
        case .trainAsPlanned: return Palette.accent
        case .capIntensity, .swap: return Palette.caution
        case .activeRecovery: return Palette.critical
        case .rest: return Palette.secondaryText
        }
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            ForEach(panel.reasons, id: \.self) { reason in
                Text(reason)
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
