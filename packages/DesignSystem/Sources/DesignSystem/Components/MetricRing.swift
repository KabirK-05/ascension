import SwiftUI

/// Progress towards a target, as a ring with the number in it.
///
/// The arrangement follows Apple Fitness and MacroFactor: the value is the
/// hero and lives inside the ring, the unit is inline and small (§3.2), and the
/// noun sits underneath. Past the target the overflow draws back over the ring
/// in the caution colour — the only second colour this component can show, and
/// it means status, not decoration (§2.4).
public struct MetricRing: View {

    public enum Size {
        case hero
        case compact
    }

    private let label: String
    private let value: Double
    private let goal: Double
    private let unit: String?
    private let size: Size
    private let fractionDigits: Int

    /// A ring is geometry, not text. It grows with Dynamic Type so the number
    /// inside stays legible, but the growth is capped: left uncapped, an
    /// accessibility size makes the ring wider than the phone and drags every
    /// card on the screen out with it.
    private static let growthCap: CGFloat = 1.32

    @ScaledMetric(relativeTo: .largeTitle) private var heroScale: CGFloat = 1
    @ScaledMetric(relativeTo: .title3) private var compactScale: CGFloat = 1

    public init(
        _ label: String,
        value: Double,
        goal: Double,
        unit: String? = nil,
        size: Size = .compact,
        fractionDigits: Int = 0
    ) {
        LabelRule.check(label)
        self.label = label
        self.value = value
        self.goal = goal
        self.unit = unit
        self.size = size
        self.fractionDigits = fractionDigits
    }

    private var diameter: CGFloat {
        switch size {
        case .hero: return 136 * min(heroScale, Self.growthCap)
        case .compact: return 88 * min(compactScale, Self.growthCap)
        }
    }

    private var lineWidth: CGFloat {
        diameter * (size == .hero ? 0.105 : 0.12)
    }

    /// 0...1 of the first lap.
    private var filled: Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    /// 0...1 of whatever a second lap has covered.
    private var overflow: Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal - 1, 0), 1)
    }

    private var formattedValue: String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private var formattedGoal: String {
        goal.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    public var body: some View {
        VStack(spacing: Spacing.snug) {
            ZStack {
                Circle()
                    .stroke(Palette.track, lineWidth: lineWidth)
                arc(to: filled, colour: Palette.accent)
                if overflow > 0 {
                    arc(to: overflow, colour: Palette.caution)
                }
                centreValue
            }
            .frame(width: diameter, height: diameter)
            .animation(.easeOut(duration: 0.45), value: value)

            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.secondaryText)
                // §1.3 guarantees a label is at most two words, so one line is
                // the right constraint: it shrinks to fit rather than
                // hyphenating itself when a caller sets rings side by side at
                // an accessibility size.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(
            [formattedValue, "of", formattedGoal, unit].compactMap { $0 }.joined(separator: " ")
        )
    }

    private func arc(to fraction: Double, colour: Color) -> some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private var centreValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.hairline) {
            Text(formattedValue)
                .font(size == .hero ? Typography.heroValue : Typography.compactValue)
                .monospacedDigit()
                .foregroundStyle(Palette.primaryText)
            if let unit {
                Text(unit)
                    .font(Typography.unit)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        // A number that shrinks still reads; a number that truncates does not,
        // and the number is the hero of the card (§3.1).
        .minimumScaleFactor(0.4)
        .lineLimit(1)
        .padding(.horizontal, lineWidth)
    }
}

#Preview("MetricRing — dark") {
    MetricRingPreview().preferredColorScheme(.dark)
}

#Preview("MetricRing — light") {
    MetricRingPreview().preferredColorScheme(.light)
}

private struct MetricRingPreview: View {
    var body: some View {
        VStack(spacing: Spacing.section) {
            StatCard {
                MetricRing("Protein", value: 148, goal: 150, unit: "g", size: .hero)
                    .frame(maxWidth: .infinity)
            }
            StatCard {
                HStack(spacing: Spacing.section) {
                    MetricRing("Calories", value: 2140, goal: 2400)
                    MetricRing("Water", value: 3.4, goal: 3, unit: "L", fractionDigits: 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.screenMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
    }
}
