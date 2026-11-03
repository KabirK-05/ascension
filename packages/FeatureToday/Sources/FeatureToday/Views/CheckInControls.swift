import AscensionCore
import DesignSystem
import SwiftUI

/// The morning check-in (spec §F4), inside the card whose number it feeds.
///
/// Ten seconds is the requirement, so the interaction is built around the morning that
/// actually happens: nothing is sore. Every group starts unmarked, and tapping an energy
/// commits — **one tap**. Only the exceptions cost more, one tap per step per group.
///
/// Adapted from Clue's symptom sheet, where "pain free" is a first-class one-tap answer
/// rather than eight explicit noes, and from Visible's severity matrix for the idea of a
/// fixed scale read left to right. What is deliberately *not* adapted is Whoop's journal,
/// which puts a ✗/✓ pair on every row — correct for a yes/no log, and exactly the
/// twenty-four taps this screen refuses. Nothing here explains itself: there is no
/// question, no instruction and no legend, because the controls are the whole content
/// (`docs/DESIGN_RULES.md` §1.1, §1.4).
struct CheckInControls: View {
    let panel: CheckInPanel
    let cycle: (MuscleGroup) -> Void
    let submit: (Int) -> Void
    let retry: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// A tap target grows with the type, but only so far: five energy steps and their
    /// gaps have to stay inside the card at every size, so this is clamped rather than
    /// scaled without a ceiling. Below the floor is Apple's 44 pt minimum.
    @ScaledMetric(relativeTo: .subheadline) private var scaledTarget: CGFloat = 44
    private var tapTarget: CGFloat { min(max(scaledTarget, 44), 56) }

    /// Two tidy rows of four at the default size, halving and halving again as the type
    /// grows. Fixed tiers rather than an adaptive minimum, because an adaptive grid
    /// sizes its columns from a width that does not grow at the same rate as the words
    /// inside them — which is how eight short nouns end up wider than the screen.
    private var columns: [GridItem] {
        let count = if typeSize.isAccessibilitySize {
            1
        } else if typeSize >= .xLarge {
            2
        } else {
            4
        }
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.snug), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            groups
            energy
            if panel.status == .failed {
                retryControl
            }
        }
        .disabled(panel.status == .saving)
        .opacity(panel.status == .saving ? 0.5 : 1)
        .animation(.easeOut(duration: 0.2), value: panel.status)
    }

    // MARK: - Soreness

    private var groups: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.snug) {
            ForEach(panel.groups) { group in
                chip(group)
            }
        }
    }

    private func chip(_ group: CheckInGroupState) -> some View {
        Button { cycle(group.group) } label: {
            Text(group.label)
                .font(Typography.label)
                .foregroundStyle(tint(group.level))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: tapTarget)
                .padding(.horizontal, Spacing.tight)
                .background(fill(group.level),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.label)
        .accessibilityValue(group.spokenLevel)
    }

    /// `sore` is the one level with a tinted fill, so it is distinguishable from `mild`
    /// without reading the hue; VoiceOver carries the exact level either way.
    private func fill(_ level: SorenessLevel) -> Color {
        level == .sore ? Palette.critical.opacity(0.18) : Palette.surfaceRaised
    }

    private func tint(_ level: SorenessLevel) -> Color {
        switch level {
        case .none: return Palette.secondaryText
        case .mild: return Palette.caution
        case .sore: return Palette.critical
        }
    }

    // MARK: - Energy, which is also the submit

    private var energy: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.regular) {
                energyLabel
                Spacer(minLength: Spacing.snug)
                energyScale
            }
            VStack(alignment: .leading, spacing: Spacing.snug) {
                energyLabel
                energyScale
            }
        }
    }

    private var energyLabel: some View {
        Text("Energy")
            .font(Typography.label)
            .foregroundStyle(Palette.secondaryText)
            .accessibilityHidden(true)
    }

    private var energyScale: some View {
        HStack(spacing: Spacing.snug) {
            ForEach(panel.energyScale, id: \.self) { value in
                energyStep(value)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Energy")
    }

    private func energyStep(_ value: Int) -> some View {
        let chosen = panel.energy == value
        return Button { submit(value) } label: {
            Text(value.formatted())
                .font(Typography.label)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(chosen ? Palette.background : Palette.primaryText)
                .frame(width: tapTarget, height: tapTarget)
                .background(chosen ? Palette.accent : Palette.surfaceRaised,
                            in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Energy \(value)")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    // MARK: - A failed save

    private var retryControl: some View {
        Button(action: retry) {
            Text("Retry")
                .font(Typography.label)
                .foregroundStyle(Palette.critical)
                .padding(.vertical, Spacing.snug)
                .frame(maxWidth: .infinity, minHeight: tapTarget)
                .background(Palette.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry")
    }
}
