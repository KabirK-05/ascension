import SwiftUI

/// A label and a value, where the value is the larger of the two (§3.1).
///
/// The layout is adapted from Oura's readiness contributors: the noun sits
/// left, the measurement sits right, and an optional hairline track underneath
/// carries progress without spending a second number on it.
public struct ValueRow: View {

    /// How loud the value is. `hero` is for the one value a card exists for.
    public enum Emphasis {
        case standard
        case hero
    }

    private let label: String
    private let value: String
    private let unit: String?
    private let progress: Double?
    private let emphasis: Emphasis
    private let spokenValue: String?

    @ScaledMetric(relativeTo: .subheadline) private var trackHeight: CGFloat = 3

    public init(
        _ label: String,
        value: String,
        unit: String? = nil,
        progress: Double? = nil,
        emphasis: Emphasis = .standard,
        spokenValue: String? = nil
    ) {
        LabelRule.check(label)
        self.label = label
        self.value = value
        self.unit = unit
        self.progress = progress
        self.emphasis = emphasis
        self.spokenValue = spokenValue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
                    labelText
                    Spacer(minLength: Spacing.snug)
                    valueText
                }
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    labelText
                    valueText
                }
            }
            if let progress {
                track(fraction: min(max(progress, 0), 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? [value, unit].compactMap { $0 }.joined(separator: " "))
    }

    private var labelText: some View {
        Text(label)
            .font(Typography.label)
            .foregroundStyle(Palette.secondaryText)
    }

    private var valueText: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.hairline) {
            Text(value)
                .font(emphasis == .hero ? Typography.heroValue : Typography.value)
                .monospacedDigit()
                .foregroundStyle(Palette.primaryText)
            if let unit {
                Text(unit)
                    .font(Typography.unit)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func track(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: trackHeight)
        .animation(.easeOut(duration: 0.45), value: fraction)
    }
}

#Preview("ValueRow — dark") {
    ValueRowPreview().preferredColorScheme(.dark)
}

#Preview("ValueRow — light") {
    ValueRowPreview().preferredColorScheme(.light)
}

private struct ValueRowPreview: View {
    var body: some View {
        VStack(spacing: Spacing.section) {
            StatCard("Today") {
                VStack(spacing: Spacing.regular) {
                    ValueRow("Protein", value: "148", unit: "g", progress: 148.0 / 150.0)
                    ValueRow("Steps", value: "11,240", progress: 1)
                    ValueRow("Sleep", value: "7h42", progress: 7.7 / 7.5)
                    ValueRow("Resting HR", value: "52", unit: "bpm", spokenValue: "52 beats per minute")
                }
            }
            StatCard("Weight") {
                ValueRow("7-day", value: "73.6", unit: "kg", emphasis: .hero)
            }
        }
        .padding(Spacing.screenMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
    }
}
