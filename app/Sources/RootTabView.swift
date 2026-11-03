import SwiftUI

/// The four tabs from spec §4. Settings lives inside Today, not as a fifth tab.
///
/// Each tab is built by the composition root, so this file knows which screens exist and
/// nothing about where a step count comes from.
struct RootTabView: View {
    let composition: AppComposition

    /// Owned here because Today's nutrition card asks to open Eat, and the only thing that
    /// can answer that is whatever holds the selection. It is the second half of the
    /// cross-feature link the shell exists to close.
    @State private var selection: Tabs = .today

    private enum Tabs: Hashable {
        case today, train, eat, trends
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: Tabs.today) {
                composition.todayScreen(openEat: { selection = .eat })
            }
            Tab("Train", systemImage: "figure.strengthtraining.traditional", value: Tabs.train) {
                composition.trainScreen()
            }
            Tab("Eat", systemImage: "fork.knife", value: Tabs.eat) {
                composition.eatScreen()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: Tabs.trends) {
                composition.trendsScreen()
            }
        }
    }
}
