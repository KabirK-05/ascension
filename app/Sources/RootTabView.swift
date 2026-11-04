import DesignSystem
import SwiftUI

/// The four tabs from spec §4, plus the gear that §4 allows beside them.
///
/// Each tab is built by the composition root, so this file knows which screens exist and
/// nothing about where a step count comes from.
struct RootTabView: View {
    let composition: AppComposition

    /// Owned here because Today's nutrition card asks to open Eat, and the only thing that
    /// can answer that is whatever holds the selection. It is the second half of the
    /// cross-feature link the shell exists to close.
    @State private var selection: Tabs = .today
    @State private var isShowingSettings = false

    private enum Tabs: Hashable {
        case today, train, eat, trends
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: Tabs.today) {
                composition.todayScreen(openEat: { selection = .eat })
                    .overlay(alignment: .topTrailing) { gear }
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
        .sheet(isPresented: $isShowingSettings) {
            SettingsScreen(composition: composition)
        }
    }

    /// Spec §4 puts Settings "inside Today or a gear". It is drawn here rather than in
    /// `FeatureToday`'s toolbar for a boundary reason: Settings is the shell's screen — it
    /// pairs the device, flips a flag and undoes a sync write — and a feature package may
    /// not know any of that exists. `TodayScreen` owns its own `NavigationStack`, so the
    /// gear sits in the trailing corner of the same band its inline title does.
    private var gear: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .tint(Palette.accent)
        .accessibilityLabel("Settings")
        .padding(.trailing, Spacing.snug)
    }
}
