import AscensionCore
import DesignSystem
import SwiftUI

/// The one manual training input (spec §F2): top-set weight × reps, per exercise.
///
/// Hevy's set table is the layout — the exercise on the left, kg and reps as two small
/// fields on the right — minus everything that makes it a live logger. Apple records the
/// session; this records the one thing Apple does not. Every field opens prefilled with
/// the load the progression rule already chose, so the twenty seconds are confirmations,
/// not data entry.
struct TopSetLogScreen: View {
    let sessionName: String?
    @State var drafts: [TopSetDraft]
    let onSave: ([TopSetDraft]) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: String?

    var body: some View {
        NavigationStack {
            Form {
                ForEach($drafts) { $draft in
                    TopSetRow(draft: $draft, focused: $focused)
                }
            }
            .navigationTitle(sessionName ?? "Top sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(drafts)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    Spacer()
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { focused = nil }
                }
            }
        }
    }
}

private struct TopSetRow: View {
    @Binding var draft: TopSetDraft
    @FocusState.Binding var focused: String?

    // Fixed, and wide enough for a three-digit leg press: the two columns have to line
    // up down the sheet, and a field that resizes with its contents never does.
    @ScaledMetric(relativeTo: .title2) private var weightWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .title2) private var repsWidth: CGFloat = 48

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
            Text(draft.name)
                .font(Typography.label)
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: Spacing.snug)
            field(value: $draft.weightKg, unit: "kg", id: "\(draft.id)/kg", width: weightWidth)
            field(value: $draft.reps, unit: "reps", id: "\(draft.id)/reps", width: repsWidth)
        }
    }

    private func field(value: Binding<Double?>, unit: String, id: String, width: CGFloat) -> some View {
        HStack(spacing: Spacing.hairline) {
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typography.value)
                .monospacedDigit()
                .frame(width: width)
                .focused($focused, equals: id)
            Text(unit)
                .font(Typography.unit)
                .foregroundStyle(Palette.secondaryText)
        }
        .accessibilityLabel("\(draft.name) \(unit)")
    }

    private func field(value: Binding<Int?>, unit: String, id: String, width: CGFloat) -> some View {
        HStack(spacing: Spacing.hairline) {
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(Typography.value)
                .monospacedDigit()
                .frame(width: width)
                .focused($focused, equals: id)
            Text(unit)
                .font(Typography.unit)
                .foregroundStyle(Palette.secondaryText)
        }
        .accessibilityLabel("\(draft.name) \(unit)")
    }
}
