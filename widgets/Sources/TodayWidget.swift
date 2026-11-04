import DesignSystem
import SwiftUI
import SystemSurfaces
import WidgetKit

/// Today, on the Home Screen. Answers the tab's own question: **what do I do today?**
///
/// Readiness is the hero and the session is the answer, which is the same order the tab
/// uses. Nothing else fits in a small widget and nothing else belongs in one.
///
/// Mobbin references (§7.1): Apple Fitness and MyFitnessPal widgets — one number, one
/// noun, no sentence.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SurfaceProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(Palette.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Readiness and today's session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let snapshot: SurfaceSnapshot?

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            WidgetValue(value: score, label: "Readiness", tint: tint)
            if let line = secondLine {
                Text(line)
                    .font(Typography.label)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(family == .systemMedium ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var score: String {
        snapshot?.readinessScore.map(String.init) ?? WidgetValue.unmeasured
    }

    /// The accent only when the verdict is to train. Colour is status, never theme (§2.4).
    private var tint: Color {
        snapshot?.verdict == .trainAsPlanned ? Palette.accent : Palette.primaryText
    }

    /// The session on a training day, the verdict on a rest day, nothing when neither is
    /// known. A medium widget has room for both.
    private var secondLine: String? {
        guard let snapshot else { return nil }
        let verdict = snapshot.verdict.map(SurfaceText.verdict)
        guard let session = snapshot.sessionName else { return verdict }
        guard family == .systemMedium, let verdict else { return session }
        return "\(session) · \(verdict)"
    }
}

#Preview("Today — small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    SurfaceEntry(date: .now, snapshot: WidgetPreviewData.day)
    SurfaceEntry(date: .now, snapshot: nil)
}

#Preview("Today — medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    SurfaceEntry(date: .now, snapshot: WidgetPreviewData.day)
}
