import AscensionCore
import Foundation
import SystemSurfaces

/// One day for the previews, so both appearances can be checked without a device that has
/// ever published a snapshot. Not sample data in a shipping path: nothing but `#Preview`
/// reads it.
enum WidgetPreviewData {
    static let day = SurfaceSnapshot(
        date: CalendarDate.literal("2026-11-03"),
        updatedAt: Timestamp(Date(), timeZone: .gmt),
        readinessScore: 74,
        verdict: .trainAsPlanned,
        sessionName: "Lower A",
        sessionDone: false,
        proteinG: 88,
        proteinTargetG: 150,
        streakDays: 12)
}
