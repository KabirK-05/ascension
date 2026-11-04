import AscensionCore
import DesignSystem
import SwiftUI

/// The session ahead and what to load it with.
///
/// Hevy's set table greys the previous entry beside the one being filled in; the same
/// idea, read-only: last time on the left of the target, so "20 kg × 11 → 22.5 kg"
/// (spec §F2) is two numbers in a row rather than a sentence.
struct NextSessionCard: View {
    let day: TrainingDay
    let targets: [ProgressionTarget]
    let canSendToWatch: Bool
    let name: (String) -> String
    let onSendToWatch: () -> Void

    var body: some View {
        StatCard(day.sessionName ?? "Next") {
            VStack(spacing: Spacing.regular) {
                ForEach(targets) { target in
                    ExerciseLoadRow(name: name(target.exerciseId), target: target)
                }
            }
            if canSendToWatch {
                Button("Send to Watch", action: onSendToWatch)
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
            }
        }
    }
}

/// An exercise, what it was last loaded with, and what it is loaded with next.
///
/// Not a `ValueRow`: an exercise name is three words often enough that `LabelRule` is
/// right to reject it as a label. The grammar is the same — identity left, measurement
/// right, the measurement larger (§3.1).
private struct ExerciseLoadRow: View {
    let name: String
    let target: ProgressionTarget

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
            Text(name)
                .font(Typography.label)
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: Spacing.snug)
            if let last = target.last {
                Text("\(TrainFormat.weight(last.weightKg))×\(last.reps)")
                    .font(Typography.detail)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryText)
            }
            targetText
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(spoken)
    }

    @ViewBuilder
    private var targetText: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.hairline) {
            Text(target.targetWeightKg.map(TrainFormat.weight) ?? "—")
                .font(Typography.value)
                .monospacedDigit()
                .foregroundStyle(target.advancing ? Palette.accent : Palette.primaryText)
            if target.targetWeightKg != nil {
                Text("kg")
                    .font(Typography.unit)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var spoken: String {
        guard let weight = target.targetWeightKg else { return "no load logged yet" }
        let next = "\(TrainFormat.weight(weight)) kilograms"
        guard let last = target.last else { return next }
        return "last \(TrainFormat.weight(last.weightKg)) for \(last.reps), next \(next)"
    }
}
