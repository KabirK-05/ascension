import DesignSystem
import SwiftUI
import SystemSurfaces
import WidgetKit

/// Eat, on the Home Screen. Answers the tab's own question: **how much protein is left?**
///
/// The ring is `DesignSystem`'s own `MetricRing`, not a second one drawn for widgets: the
/// overflow behaviour past the target, the inline unit and the label are all already
/// decided there, and a copy would drift.
///
/// Mobbin references (§7.1): MyFitnessPal and Lifesum widgets — a ring, a number, nothing
/// under it.
struct EatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EatWidget", provider: SurfaceProvider()) { entry in
            EatWidgetView(snapshot: entry.snapshot)
                .containerBackground(Palette.background, for: .widget)
        }
        .configurationDisplayName("Protein")
        .description("Protein against today's target.")
        .supportedFamilies([.systemSmall])
    }
}

struct EatWidgetView: View {
    let snapshot: SurfaceSnapshot?

    var body: some View {
        if let snapshot, snapshot.proteinTargetG > 0 {
            MetricRing("Protein",
                       value: snapshot.proteinG,
                       goal: snapshot.proteinTargetG,
                       unit: "g")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WidgetValue(value: WidgetValue.unmeasured, label: "Protein")
        }
    }
}

#Preview("Protein", as: .systemSmall) {
    EatWidget()
} timeline: {
    SurfaceEntry(date: .now, snapshot: WidgetPreviewData.day)
    SurfaceEntry(date: .now, snapshot: nil)
}
