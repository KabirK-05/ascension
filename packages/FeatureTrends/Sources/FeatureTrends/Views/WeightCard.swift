import Charts
import DesignSystem
import SwiftUI

/// Weight (spec §F6). The 7-day average is the line that matters, so it is the only one
/// drawn in the accent; the daily weigh-ins sit behind it as small, quiet points.
///
/// The header is adapted from MacroFactor's Scale Weight and Withings Health Mate's
/// Weight: the summary numbers frame the chart, and the chart carries no caption
/// explaining itself (§1.1).
///
/// There is no goal line on the chart. A rule at 68 kg pulls the Y scale down to span six
/// kilograms the user has not walked yet, and flattens the average into a straight line —
/// the one thing the card exists to show. "To goal" says the same thing in a number, so
/// the line fails the subtraction test (§2.1).
struct WeightCard: View {
    let panel: WeightPanel

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 148
    @ScaledMetric(relativeTo: .body) private var pointSize: CGFloat = 14

    var body: some View {
        StatCard("Weight") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                ValueRow("7-day", value: panel.latestAverage, unit: "kg",
                         emphasis: .hero, spokenValue: panel.spokenLatestAverage)
                chart
                ValueRow("Rate", value: panel.rate, unit: "kg/wk",
                         spokenValue: panel.spokenRate)
                ValueRow("To goal", value: panel.toGoal, unit: "kg",
                         spokenValue: panel.spokenToGoal)
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if panel.points.isEmpty && panel.average.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            Chart {
                ForEach(panel.points) { point in
                    PointMark(x: .value("Day", point.date), y: .value("Weight", point.value))
                        .symbolSize(pointSize)
                        .foregroundStyle(Palette.tertiaryText)
                }

                ForEach(panel.average) { point in
                    LineMark(x: .value("Day", point.date), y: .value("Average", point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Palette.accent)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel() }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Palette.separator.opacity(0.5))
                    AxisValueLabel()
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(panel.chartDescription)
        }
    }
}
