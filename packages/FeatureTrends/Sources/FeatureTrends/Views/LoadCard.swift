import AscensionEngines
import Charts
import DesignSystem
import SwiftUI

/// Load management (spec §F6): weekly load, the acute:chronic band, the layoff spike, and
/// the deload prompt when the cadence week arrives.
///
/// The band is drawn as a shaded optimal region behind the ratio, adapted from WHOOP's
/// strain target — the reading is "inside or outside", which a region gives without
/// spending a sentence on it. The deload prompt and the spike are status words, not
/// paragraphs (§1.1, §2.3).
struct LoadCard: View {
    let panel: LoadPanel

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 96

    var body: some View {
        StatCard("Load") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
                    ValueRow("Ratio", value: panel.ratio,
                             emphasis: .hero, spokenValue: panel.spokenRatio)
                    Spacer(minLength: Spacing.snug)
                    status
                }
                chart
                if let week = panel.deloadWeek {
                    ValueRow("Deload", value: "Week \(week)",
                             spokenValue: "Deload due, week \(week) of the block")
                }
            }
        }
    }

    /// The band as one word, coloured by status and nothing else (§2.4). The spike
    /// outranks it: after a layoff the ratio is the less useful of the two facts.
    @ViewBuilder
    private var status: some View {
        if panel.spikeAfterLayoff {
            chip("Spike", tint: Palette.caution,
                 spoken: "Spike after \(panel.layoffDays) days off")
        } else if let band = panel.band {
            chip(panel.bandName, tint: tint(for: band), spoken: panel.bandName)
        }
    }

    private func chip(_ text: String, tint: Color, spoken: String) -> some View {
        Text(text)
            .font(Typography.cardLabel)
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.snug)
            .padding(.vertical, Spacing.tight)
            .background(tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityLabel(spoken)
    }

    /// Only a band that needs action takes a colour of its own. Optimal is the resting
    /// state and gets the accent; detraining is neither good nor bad and stays neutral.
    private func tint(for band: AcwrBand) -> Color {
        switch band {
        case .optimal: return Palette.accent
        case .caution: return Palette.caution
        case .highRisk: return Palette.critical
        case .detraining: return Palette.secondaryText
        }
    }

    @ViewBuilder
    private var chart: some View {
        if panel.weekly.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            Chart(panel.weekly) { point in
                BarMark(x: .value("Week", point.date, unit: .weekOfYear),
                        y: .value("Load", point.value))
                    .cornerRadius(Radius.cell)
                    .foregroundStyle(Palette.accent.opacity(0.75))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel() }
            }
            .chartYAxis(.hidden)
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(panel.chartDescription)
        }
    }
}
