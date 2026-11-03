import SwiftUI
import FeatureEat
import FeatureToday
import FeatureTrain
import FeatureTrends

/// The four tabs from spec §4. Settings lives inside Today, not as a fifth tab.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayScreen()
            }
            Tab("Train", systemImage: "figure.strengthtraining.traditional") {
                TrainScreen()
            }
            Tab("Eat", systemImage: "fork.knife") {
                EatScreen()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis") {
                TrendsScreen()
            }
        }
    }
}

#Preview {
    RootTabView()
}
