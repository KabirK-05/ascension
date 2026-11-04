import AscensionCore
import DesignSystem
import SwiftUI

/// The session behind: what it cost, and a way into the full debrief.
///
/// Three numbers, which is what Apple Fitness's own session rows show, and a tap for the
/// rest (§5.3 — tapping a number is the disclosure mechanism, not an expander).
struct LastSessionCard: View {
    let debrief: SessionDebrief
    let timeZone: TimeZone

    var body: some View {
        StatCard("Last") {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
                Text(debrief.day.sessionName ?? "")
                    .font(Typography.label)
                    .foregroundStyle(Palette.primaryText)
                Spacer(minLength: Spacing.snug)
                Text(TrainFormat.day(debrief.day.date, timeZone: timeZone))
                    .font(Typography.detail)
                    .foregroundStyle(Palette.tertiaryText)
            }
            SessionMetrics(session: debrief.session, includeMaximum: false)
        }
    }
}

/// What Apple recorded: duration, energy, heart rate. The same four rows the debrief
/// opens with, so the card and the screen behind it cannot disagree.
struct SessionMetrics: View {
    let session: CompletedSession
    var includeMaximum = true

    var body: some View {
        VStack(spacing: Spacing.regular) {
            let duration = TrainFormat.duration(minutes: session.durationMinutes)
            ValueRow("Duration", value: duration.value, unit: duration.unit,
                     spokenValue: "\(session.durationMinutes) minutes")
            if let energy = session.activeEnergyKcal {
                ValueRow("Energy", value: "\(Int(energy.rounded()))", unit: "kcal")
            }
            if let average = session.hrAvgBpm {
                ValueRow("HR avg", value: "\(average)", unit: "bpm",
                         spokenValue: "\(average) beats per minute average")
            }
            if includeMaximum, let peak = session.hrMaxBpm {
                ValueRow("HR max", value: "\(peak)", unit: "bpm",
                         spokenValue: "\(peak) beats per minute peak")
            }
        }
    }
}
