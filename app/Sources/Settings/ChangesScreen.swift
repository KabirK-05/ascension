import AscensionCore
import DesignSystem
import SwiftUI

/// Settings → Changes. Answers one question: **what did Muse change?**
///
/// A plain `List` of one line each — what changed, and when — with Undo as a swipe action
/// on the two kinds that can be put back. The date is the second half of the same line
/// rather than a caption under it (§1.1), separated by the same `·` the daily log uses.
///
/// An empty list shows nothing at all. There is no "no changes yet" paragraph: §1.4 is
/// explicit that an empty state is a control or nothing, and here there is no control to
/// offer because the list fills itself.
struct ChangesScreen: View {
    @State private var model: ChangesModel

    init(composition: AppComposition) {
        _model = State(initialValue: ChangesModel(composition: composition))
    }

    var body: some View {
        List {
            ForEach(model.rows) { row in
                ChangeRow(change: row)
                    .swipeActions(edge: .trailing) {
                        if row.canUndo {
                            Button("Undo") { Task { await model.undo(row) } }
                                .tint(Palette.accent)
                        }
                    }
            }
        }
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

/// One write, on one line.
struct ChangeRow: View {
    let change: RecordedChange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Text(change.summary)
                .font(Typography.label)
                .foregroundStyle(change.undoneAt == nil ? Palette.primaryText : Palette.tertiaryText)
                .strikethrough(change.undoneAt != nil)
            Spacer(minLength: Spacing.snug)
            Text(Stamp.day(change.at))
                .font(Typography.detail)
                .foregroundStyle(Palette.tertiaryText)
                .monospacedDigit()
        }
    }
}

extension Stamp {
    /// `Nov 5` — the shortest thing that still identifies the day.
    static func day(_ stamp: Timestamp) -> String {
        guard let instant = stamp.date else { return stamp.rawValue }
        return instant.formatted(.dateTime.month(.abbreviated).day())
    }
}
