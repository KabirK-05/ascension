import DesignSystem
import SwiftUI

/// Trends (spec §F6). Answers one question: **is it working?**
///
/// Weight first, because the 7-day average is the answer; then the calorie suggestion
/// when the engine proposes one, because it is the only action on the tab; then load,
/// consistency and the vitals that explain the first two. The Sunday review (§F7) sits at
/// the top on the day it covers, since on that day it *is* the answer.
///
/// Every number comes from `TrendsEngine` by way of ``TrendsPresenter``. This package
/// depends on `AscensionCore`, `AscensionEngines` and `DesignSystem` and nothing else;
/// the snapshot and the one write both arrive through protocols declared here.
public struct TrendsScreen: View {
    @State private var model: TrendsModel

    public init(dataSource: any TrendsDataSource = DefaultTrendsDataSource(),
                acceptor: (any SuggestionAcceptor)? = nil,
                reviewWriter: (any WeeklyReviewWriter)? = nil) {
        _model = State(initialValue: TrendsModel(dataSource: dataSource,
                                                 acceptor: acceptor,
                                                 reviewWriter: reviewWriter))
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .navigationTitle("Trends")
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

    private func cards(_ presentation: TrendsPresentation) -> some View {
        ScrollView {
            TrendsCards(presentation: presentation, acceptState: model.acceptState) { id in
                Task { await model.accept(suggestionId: id) }
            }
        }
        .refreshable { await model.load() }
    }
}

/// The tab's cards, in order.
///
/// Split out from ``TrendsScreen`` so that what a screenshot renders is the same view the
/// screen scrolls — a second stack built for pictures would drift from the real one.
struct TrendsCards: View {
    let presentation: TrendsPresentation
    let acceptState: TrendsModel.AcceptState
    let accept: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            if let review = presentation.review {
                WeeklyReviewCard(panel: review)
            }
            WeightCard(panel: presentation.weight)
            if let suggestion = presentation.suggestion {
                SuggestionCard(panel: suggestion, state: acceptState, accept: accept)
            }
            LoadCard(panel: presentation.load)
            HabitsCard(panel: presentation.habits)
            if !presentation.series.isEmpty {
                VitalsCard(panels: presentation.series)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.section)
    }
}

#Preview("Trends — dark") {
    TrendsScreen(dataSource: FixtureTrendsDataSource(TrendsFixtures.cutting),
                 acceptor: NoopAcceptor())
        .preferredColorScheme(.dark)
}

#Preview("Trends — light") {
    TrendsScreen(dataSource: FixtureTrendsDataSource(TrendsFixtures.cutting),
                 acceptor: NoopAcceptor())
        .preferredColorScheme(.light)
}

#Preview("Sunday review — dark") {
    TrendsScreen(dataSource: FixtureTrendsDataSource(TrendsFixtures.sundayReview),
                 acceptor: NoopAcceptor(),
                 reviewWriter: TemplateReviewWriter())
        .preferredColorScheme(.dark)
}

#Preview("Sunday review — light") {
    TrendsScreen(dataSource: FixtureTrendsDataSource(TrendsFixtures.sundayReview),
                 acceptor: NoopAcceptor(),
                 reviewWriter: TemplateReviewWriter())
        .preferredColorScheme(.light)
}

#Preview("Layoff spike") {
    TrendsScreen(dataSource: FixtureTrendsDataSource(TrendsFixtures.layoff))
        .preferredColorScheme(.dark)
}

#Preview("First launch") {
    TrendsScreen(dataSource: DefaultTrendsDataSource(timezone: "America/Toronto"))
        .preferredColorScheme(.dark)
}
