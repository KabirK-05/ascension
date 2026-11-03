import AscensionCore
import DesignSystem
import SwiftUI

/// Today (spec §F1). Answers one question: **what do I do today?**
///
/// Five cards, which is the ceiling (§5.2), and fewer on a rest day: readiness, the
/// session, nutrition, the day's measurements, and the consistency grid. The summary
/// line and the readiness hero answer the question above the fold at the default type
/// size (§5.1); everything below it is detail that may scroll.
///
/// Both actions on the screen are injected. Sending a session to the Watch is
/// WorkoutKit's job and belongs to the Train ticket; opening Eat belongs to the shell.
/// This package depends on `AscensionCore`, `AscensionEngines` and `DesignSystem` and
/// nothing else.
public struct TodayScreen: View {
    @State private var model: TodayModel

    private let sendToWatch: ((SessionKind) async throws -> Void)?
    private let openEat: (() -> Void)?

    public init(dataSource: any TodayDataSource = DefaultTodayDataSource(),
                sendToWatch: ((SessionKind) async throws -> Void)? = nil,
                openEat: (() -> Void)? = nil) {
        _model = State(initialValue: TodayModel(dataSource: dataSource))
        self.sendToWatch = sendToWatch
        self.openEat = openEat
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed:
            retry
        case .ready(let presentation):
            cards(presentation)
                .navigationTitle(
                    presentation.date.formatted(
                        .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                )
        }
    }

    /// A failed load offers the control, not an explanation of itself (§1.4).
    private var retry: some View {
        Button("Retry") {
            Task { await model.load() }
        }
        .font(Typography.label)
        .foregroundStyle(Palette.accent)
    }

    private func cards(_ presentation: TodayPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                summary(presentation.summary)
                ReadinessCard(panel: presentation.readiness)
                if let session = presentation.session {
                    SessionCard(plan: session, sendToWatch: sendToWatch)
                }
                NutritionCard(panel: presentation.nutrition, openEat: openEat)
                MeasurementsCard(rows: presentation.measurements)
                consistency(presentation.consistency)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.section)
        }
        .refreshable { await model.load() }
    }

    private func summary(_ text: String) -> some View {
        Text(text)
            .font(Typography.label)
            .foregroundStyle(Palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.tight)
    }

    private func consistency(_ panel: ConsistencyPanel) -> some View {
        StatCard("Consistency") {
            ConsistencyGrid(days: panel.days,
                            endingOn: panel.endDate,
                            thresholds: panel.thresholds,
                            calendar: panel.calendar)
        }
    }
}

#Preview("Today — dark") {
    TodayScreen(dataSource: FixtureDataSource(TodayFixtures.trainingDay),
                sendToWatch: { _ in },
                openEat: {})
        .preferredColorScheme(.dark)
}

#Preview("Today — light") {
    TodayScreen(dataSource: FixtureDataSource(TodayFixtures.trainingDay),
                sendToWatch: { _ in },
                openEat: {})
        .preferredColorScheme(.light)
}

#Preview("Rest day — dark") {
    TodayScreen(dataSource: FixtureDataSource(TodayFixtures.restDay),
                sendToWatch: { _ in },
                openEat: {})
        .preferredColorScheme(.dark)
}

#Preview("Rest day — light") {
    TodayScreen(dataSource: FixtureDataSource(TodayFixtures.restDay),
                sendToWatch: { _ in },
                openEat: {})
        .preferredColorScheme(.light)
}

#Preview("Sore — swap") {
    TodayScreen(dataSource: FixtureDataSource(TodayFixtures.soreDay),
                sendToWatch: { _ in },
                openEat: {})
        .preferredColorScheme(.dark)
}

#Preview("First launch") {
    TodayScreen(dataSource: FixtureDataSource(TodayFixtures.emptyDay))
        .preferredColorScheme(.dark)
}
