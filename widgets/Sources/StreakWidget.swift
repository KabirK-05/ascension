import DesignSystem
import SwiftUI
import SystemSurfaces
import WidgetKit

/// The streak. One number, and the rule behind it lives in `StreakRule` where it is
/// tested — a widget that computed its own would be the one surface nothing checks.
///
/// Mobbin references (§7.1): Strava's streak widget — a count and a noun, which is the
/// whole of it once the flame and the encouragement are removed.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: SurfaceProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(Palette.background, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Consecutive days kept.")
        .supportedFamilies([.systemSmall])
    }
}

struct StreakWidgetView: View {
    let snapshot: SurfaceSnapshot?

    var body: some View {
        WidgetValue(value: value, unit: unit, label: "Streak", tint: tint)
    }

    private var value: String {
        snapshot.map { String($0.streakDays) } ?? WidgetValue.unmeasured
    }

    private var unit: String? {
        guard let snapshot else { return nil }
        return snapshot.streakDays == 1 ? "day" : "days"
    }

    /// The accent only while the streak is running. Zero is a fact, not a failure, and it
    /// is drawn in the ordinary colour.
    private var tint: Color {
        (snapshot?.streakDays ?? 0) > 0 ? Palette.accent : Palette.primaryText
    }
}

#Preview("Streak", as: .systemSmall) {
    StreakWidget()
} timeline: {
    SurfaceEntry(date: .now, snapshot: WidgetPreviewData.day)
    SurfaceEntry(date: .now, snapshot: nil)
}
