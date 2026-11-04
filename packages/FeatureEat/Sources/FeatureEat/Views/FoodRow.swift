import AscensionCore
import DesignSystem
import SwiftUI

/// One food, one number.
///
/// The number is protein, on every row on this tab, because protein is the question
/// the tab answers (design rule 2.1) — calories live on the meal header and in the
/// day's totals. The portion sits inline beside the name, never under it: a second
/// line under a title is the shape rule 1.1 exists to forbid.
struct FoodRow: View {
    let name: String
    let portion: String?
    let proteinG: Double
    var state: HealthWriteState = .written

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
            nameAndPortion
            Spacer(minLength: Spacing.snug)
            if let symbol = state.symbol {
                Image(systemName: symbol)
                    .font(Typography.detail)
                    .foregroundStyle(Palette.caution)
                    .accessibilityHidden(true)
            }
            protein
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(spoken)
    }

    @ViewBuilder
    private var nameAndPortion: some View {
        let title = Text(name).foregroundStyle(Palette.primaryText)
        let detail = portion.map {
            Text($0).font(Typography.detail).foregroundStyle(Palette.tertiaryText)
        }
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                title
                detail
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
                title
                detail
            }
        }
    }

    private var protein: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.hairline) {
            Text(Figure.whole(proteinG))
                .font(Typography.value)
                .monospacedDigit()
                .foregroundStyle(Palette.primaryText)
            Text("g")
                .font(Typography.unit)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var spoken: String {
        let base = [portion, "\(Figure.whole(proteinG)) grams protein"]
            .compactMap { $0 }
            .joined(separator: ", ")
        guard let note = state.spokenNote else { return base }
        return "\(base), \(note)"
    }
}

extension HealthWriteState {
    /// A symbol only when there is something wrong: status that has no words
    /// (design rule 2.3).
    var symbol: String? {
        switch self {
        case .written: return nil
        case .partial, .notWritten: return "heart.slash"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var spokenNote: String? {
        switch self {
        case .written: return nil
        case .partial: return "partly in Apple Health"
        case .notWritten: return "not in Apple Health"
        case .failed: return "failed to write to Apple Health"
        }
    }
}
