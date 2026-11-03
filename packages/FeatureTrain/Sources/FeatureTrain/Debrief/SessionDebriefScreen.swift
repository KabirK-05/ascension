import AscensionCore
import DesignSystem
import SwiftUI

/// What happened in one session (spec §F2).
///
/// The zone list is WHOOP's and Strava's shape — one row per zone, the bar carrying the
/// share and the minutes read off the right — built from `ValueRow` so it is the same
/// row as everywhere else in the app rather than a second chart language.
struct SessionDebriefScreen: View {
    let debrief: SessionDebrief
    let timeZone: TimeZone
    let onLogTopSets: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                StatCard {
                    SessionMetrics(session: debrief.session)
                }
                if !debrief.zones.isEmpty {
                    StatCard("Zones") { zones }
                }
                if let conditioning = debrief.conditioning, conditioning.id != debrief.session.id,
                   let zones = debrief.conditioningZones {
                    StatCard("Finisher") {
                        FinisherRows(session: conditioning, zones: zones,
                                     drifted: debrief.conditioningDrifted)
                    }
                }
                if let comparison = debrief.comparison {
                    StatCard("Change") { ChangeRows(comparison: comparison) }
                }
                if let onLogTopSets {
                    Button("Log top sets", action: onLogTopSets)
                        .buttonStyle(.bordered)
                        .tint(Palette.accent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.screenMargin)
        }
        .background(Palette.background)
        .navigationTitle(debrief.day.sessionName ?? TrainFormat.day(debrief.day.date, timeZone: timeZone))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var zones: some View {
        ZoneRows(zones: debrief.zones)
    }
}

/// One row per zone: the bar carries the share, the minutes are read off the right.
struct ZoneRows: View {
    let zones: ZoneAnalysis

    var body: some View {
        VStack(spacing: Spacing.regular) {
            ForEach(1...5, id: \.self) { zone in
                ValueRow("Zone \(zone)",
                         value: "\(Int(zones.minutes(inZone: zone).rounded()))",
                         unit: "min",
                         progress: zones.share(ofZone: zone))
            }
        }
    }
}

/// The conditioning work, and whether it stayed where it was meant to.
///
/// Spec §F2: a Zone 2 effort that spent more of its time above Zone 2 than in it did not
/// do the work it was for. The flag is the fact — the zone it actually sat in — not a
/// sentence about it.
private struct FinisherRows: View {
    let session: CompletedSession
    let zones: ZoneAnalysis
    let drifted: Bool

    var body: some View {
        VStack(spacing: Spacing.regular) {
            let duration = TrainFormat.duration(minutes: session.durationMinutes)
            ValueRow("Duration", value: duration.value, unit: duration.unit)
            if let average = session.hrAvgBpm {
                ValueRow("HR avg", value: "\(average)", unit: "bpm",
                         spokenValue: "\(average) beats per minute average")
            }
            ValueRow("Zone 2", value: "\(Int(zones.minutes(inZone: 2).rounded()))", unit: "min",
                     progress: zones.share(ofZone: 2))
            if drifted, let dominant = zones.dominantZone {
                ValueRow("Drift", value: "Zone \(dominant)")
            }
        }
    }
}

/// This session against the last one of the same kind. Deltas only — the absolute
/// numbers are already three rows up.
private struct ChangeRows: View {
    let comparison: SessionComparison

    var body: some View {
        VStack(spacing: Spacing.regular) {
            ValueRow("Duration", value: TrainFormat.signed(comparison.durationMinutes), unit: "min")
            if let energy = comparison.activeEnergyKcal {
                ValueRow("Energy", value: TrainFormat.signed(energy), unit: "kcal")
            }
            if let average = comparison.hrAvgBpm {
                ValueRow("HR avg", value: TrainFormat.signed(average), unit: "bpm")
            }
            if let peak = comparison.hrMaxBpm {
                ValueRow("HR max", value: TrainFormat.signed(peak), unit: "bpm")
            }
        }
    }
}
