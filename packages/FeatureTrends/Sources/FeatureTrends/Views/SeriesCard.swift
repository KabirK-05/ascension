import Charts
import DesignSystem
import SwiftUI

/// One vitals or sleep trend (spec §F6): the latest value and the line behind it.
///
/// The sparkline carries no axis at all. Adapted from Eight Sleep's resting-heart-rate
/// screen, where the number is the answer and the line is only its shape — an axis here
/// would be two more labels explaining a chart that does not need explaining (§2.1).
struct SeriesCard: View {
    let panel: SeriesPanel

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var chartWidth: CGFloat = 84

    /// The sparkline is dropped rather than squeezed once the type size needs the width
    /// for the number — the number is the answer, and §4.3 means Dynamic Type wins.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.regular) {
                sparkline
                ValueRow(panel.label, value: panel.latest, unit: panel.unit,
                         spokenValue: panel.spokenLatest)
            }
            ValueRow(panel.label, value: panel.latest, unit: panel.unit,
                     spokenValue: panel.spokenLatest)
        }
    }

    private var sparkline: some View {
        Chart(panel.points) { point in
            LineMark(x: .value("Day", point.date), y: .value(panel.label, point.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .foregroundStyle(Palette.accent.opacity(0.8))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: chartWidth, height: chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(panel.chartDescription)
    }
}

/// The vitals and sleep series, in one card.
struct VitalsCard: View {
    let panels: [SeriesPanel]

    var body: some View {
        StatCard("Vitals") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                ForEach(panels) { SeriesCard(panel: $0) }
            }
        }
    }
}
