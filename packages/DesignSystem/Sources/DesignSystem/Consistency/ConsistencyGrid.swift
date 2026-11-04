import SwiftUI

/// Seventeen weeks of days, one cell each, read at a glance (§6).
///
/// There is no legend, no axis, no month label and no count underneath,
/// because none of them is needed to answer *am I consistent?* — and §2.1 says
/// an element that the screen still works without does not ship. Tapping a
/// cell is the one affordance, and it reveals that day's four values (§6.4).
public struct ConsistencyGrid: View {
    private let slots: [[ConsistencyDay?]]
    private let thresholds: ConsistencyThresholds

    @State private var selected: ConsistencyDay?

    public init(
        days: [ConsistencyDay],
        endingOn endDate: Date = .now,
        thresholds: ConsistencyThresholds = .standard,
        calendar: Calendar = .current
    ) {
        self.slots = ConsistencyLayout.slots(for: days, endingOn: endDate, calendar: calendar)
        self.thresholds = thresholds
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.roomy) {
            grid
            if let selected, let wins = selected.wins {
                reveal(on: selected.date, wins: wins)
            }
        }
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    private var grid: some View {
        HStack(spacing: Spacing.gridCellGap) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, week in
                VStack(spacing: Spacing.gridCellGap) {
                    ForEach(0..<ConsistencyLayout.daysPerWeek, id: \.self) { row in
                        cell(week.indices.contains(row) ? week[row] : nil)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Consistency")
    }

    @ViewBuilder
    private func cell(_ day: ConsistencyDay?) -> some View {
        if let day, let wins = day.wins {
            let score = wins.intensity(against: thresholds)
            Button {
                selected = (selected == day) ? nil : day
            } label: {
                swatch(intensity: score, isSelected: selected == day)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.spokenDate(day.date))
            .accessibilityValue("\(score) of 4")
        } else if let day {
            swatch(intensity: 0, isSelected: false)
                .accessibilityLabel(Self.spokenDate(day.date))
                .accessibilityValue("No data")
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    private func swatch(intensity: Int, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: Radius.cell, style: .continuous)
            .fill(Palette.consistency(intensity))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.cell, style: .continuous)
                        .strokeBorder(Palette.primaryText, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
    }

    private func reveal(on date: Date, wins: DayWins) -> some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(Typography.detail)
                .foregroundStyle(Palette.tertiaryText)
            ValueRow("Session", value: wins.session.display)
            ValueRow("Protein", value: wins.proteinGrams.formatted(), unit: "g")
            ValueRow("Steps", value: wins.steps.formatted())
            ValueRow(
                "Sleep",
                value: Self.sleepText(wins.sleepHours),
                spokenValue: Self.spokenSleep(wins.sleepHours)
            )
        }
        .transition(.opacity)
    }

    static func spokenDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// `7h42`, never `7.7 h` — the unit is inline and the precision is real (§3.2, §3.4).
    static func sleepText(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return "\(total / 60)h\(String(format: "%02d", total % 60))"
    }

    static func spokenSleep(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return "\(total / 60) hours \(total % 60) minutes"
    }
}

#Preview("ConsistencyGrid — dark") {
    ConsistencyGridPreview().preferredColorScheme(.dark)
}

#Preview("ConsistencyGrid — light") {
    ConsistencyGridPreview().preferredColorScheme(.light)
}

private struct ConsistencyGridPreview: View {
    var body: some View {
        VStack(spacing: Spacing.section) {
            StatCard("Consistency") {
                ConsistencyGrid(days: SampleData.consistency, endingOn: SampleData.today)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.screenMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
    }
}
