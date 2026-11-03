import SwiftUI

/// A card. It holds a label and content, and there is nowhere to put a sentence.
///
/// This is deliberate (§1.1). There is no `subtitle`, no `caption`, no
/// `footnote` and no second text slot of any kind, so the generated-card
/// pattern this project is designed against cannot be expressed through it. The
/// label itself is checked against `LabelRule` in debug builds.
public struct StatCard<Content: View>: View {
    private let label: String?
    private let content: Content

    /// A card under a label.
    public init(_ label: String, @ViewBuilder content: () -> Content) {
        LabelRule.check(label)
        self.label = label
        self.content = content()
    }

    /// A card whose content names itself.
    public init(@ViewBuilder content: () -> Content) {
        self.label = nil
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            if let label {
                Text(label)
                    .font(Typography.cardLabel)
                    .foregroundStyle(Palette.secondaryText)
            }
            content
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
    }
}

#Preview("StatCard — dark") {
    StatCardPreview().preferredColorScheme(.dark)
}

#Preview("StatCard — light") {
    StatCardPreview().preferredColorScheme(.light)
}

private struct StatCardPreview: View {
    var body: some View {
        VStack(spacing: Spacing.regular) {
            StatCard("Readiness") {
                Text("74")
                    .font(Typography.heroValue)
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
            }
            StatCard {
                ValueRow("Weight", value: "73.6", unit: "kg")
            }
        }
        .padding(Spacing.screenMargin)
        .frame(maxHeight: .infinity)
        .background(Palette.background)
    }
}
