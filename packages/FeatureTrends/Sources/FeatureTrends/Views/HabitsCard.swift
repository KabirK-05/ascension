import DesignSystem
import SwiftUI

/// Protein hit-rate and adherence (spec §F2, §F6).
///
/// Two percentages and the counts behind them. The counts are the value's own detail, so
/// they live in the VoiceOver value rather than in a second line of text (§1.1).
struct HabitsCard: View {
    let panel: HabitsPanel

    var body: some View {
        StatCard("Consistency") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                ValueRow("Protein", value: panel.proteinHitRate,
                         progress: fraction(panel.proteinHitRate),
                         spokenValue: "\(panel.proteinHitRate), "
                             + "\(panel.proteinHitDays) of \(panel.windowDays) days")
                ValueRow("Adherence", value: panel.adherence,
                         progress: fraction(panel.adherence),
                         spokenValue: "\(panel.adherence), \(panel.completedSessions) of "
                             + "\(panel.plannedSessions) sessions")
            }
        }
    }

    /// The track under a percentage, read back off the string the engine's number was
    /// written to — so the bar and the number can never disagree.
    private func fraction(_ percent: String) -> Double? {
        guard let value = Double(percent.replacingOccurrences(of: "%", with: "")) else {
            return nil
        }
        return value / 100
    }
}
