import DesignSystem
import SwiftUI

/// A number with its noun under it, which is every widget in this bundle.
///
/// `docs/DESIGN_RULES.md` applies here exactly as it does on a screen, and a widget is the
/// most tempting place in iOS to add a line explaining the number. There is nowhere to put
/// one: this view takes a value, an optional inline unit and a label, and that is all it
/// can draw. The value is the largest thing on it (§3.1) and the label is smaller and
/// quieter (§3.1), never bold.
struct WidgetValue: View {
    let value: String
    var unit: String?
    let label: String
    var tint: Color = Palette.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.hairline) {
                Text(value)
                    .font(Typography.heroValue)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(Typography.unit)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Text(label)
                .font(Typography.cardLabel)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// What a widget shows before the app has ever published, and on a build with no app
/// group. An em dash, not a sentence (§1.4).
extension WidgetValue {
    static let unmeasured = "—"
}
