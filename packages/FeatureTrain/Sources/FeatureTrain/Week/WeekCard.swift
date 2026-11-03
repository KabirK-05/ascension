import AscensionCore
import DesignSystem
import SwiftUI

/// The week, and whether it is being kept.
///
/// Apple Fitness's weekly step card is the shape: the one number at the top, the seven
/// days under it, nothing else. The day marks are the consistency grid's grammar at a
/// week's scale — a filled square per day, no legend and no month label (§6.3).
struct WeekCard: View {
    let week: [TrainingDay]
    let adherence: WeekAdherence
    let streak: Int
    let timeZone: TimeZone
    let today: CalendarDate
    let onSelect: (TrainingDay) -> Void

    var body: some View {
        StatCard("Week") {
            // No progress track under the percentage: the seven squares below already
            // carry it, day by day, and a bar saying the same thing again is the
            // element §2.1 asks you to remove.
            ValueRow("Adherence", value: adherenceValue, unit: adherence.percent == nil ? nil : "%",
                     emphasis: .hero, spokenValue: spokenAdherence)
            HStack(spacing: Spacing.snug) {
                ForEach(week) { day in
                    DayMark(day: day, isToday: day.date == today, onSelect: onSelect)
                }
            }
            if streak > 0 {
                ValueRow("Streak", value: "\(streak)")
            }
        }
    }

    private var adherenceValue: String {
        adherence.percent.map(String.init) ?? "—"
    }

    private var spokenAdherence: String {
        guard let percent = adherence.percent else { return "no sessions planned yet" }
        return "\(percent) percent, \(adherence.completed) of \(adherence.planned)"
    }
}

/// One day: a square, and the letter under it.
private struct DayMark: View {
    let day: TrainingDay
    let isToday: Bool
    let onSelect: (TrainingDay) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 34

    var body: some View {
        Button {
            onSelect(day)
        } label: {
            VStack(spacing: Spacing.tight) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(fill)
                    .frame(height: height)
                Text(TrainFormat.weekdayInitial(day.date.isoWeekday))
                    .font(Typography.detail)
                    .foregroundStyle(isToday ? Palette.primaryText : Palette.tertiaryText)
            }
        }
        .buttonStyle(.plain)
        .disabled(day.completedBy == nil)
        .accessibilityLabel(TrainFormat.day(day.date, timeZone: .current))
        .accessibilityValue(spokenOutcome)
    }

    /// Green is on program, red is a session owed, and a near-background fill is a day
    /// with nothing to answer for. Colour is status here and nothing else (§2.4).
    private var fill: Color {
        switch day.outcome {
        case .completed: return Palette.accent
        case .missed: return Palette.critical
        case .upcoming: return Palette.surfaceRaised
        case .rest: return Palette.track
        }
    }

    private var spokenOutcome: String {
        switch day.outcome {
        case .completed: return day.sessionName.map { "\($0), done" } ?? "done"
        case .missed: return day.sessionName.map { "\($0), missed" } ?? "missed"
        case .upcoming: return day.sessionName ?? "planned"
        case .rest: return "rest"
        }
    }
}
