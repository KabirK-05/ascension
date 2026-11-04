import SystemSurfaces
import WidgetKit

/// One entry: whatever the app last wrote to the shared container.
struct SurfaceEntry: TimelineEntry {
    let date: Date
    let snapshot: SurfaceSnapshot?
}

/// Every widget in this bundle reads the same file and nothing else.
///
/// A widget extension is a separate process with no HealthKit authorization of its own and
/// no SwiftData container, so there is nothing here to compute — the app publishes
/// `SurfaceSnapshot` after each refresh and this hands it to a view. That is also what
/// keeps a widget from ever disagreeing with the tab behind it.
///
/// The timeline holds one entry and asks to be rebuilt in half an hour. It is a floor, not
/// a promise: the app calls `WidgetCenter.reloadAllTimelines()` every time it publishes, so
/// the usual path to a fresh number is the app refreshing, and this is only the backstop
/// for a phone nobody has opened.
struct SurfaceProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 30 * 60

    private let store = SurfaceStore()

    func placeholder(in context: Context) -> SurfaceEntry {
        SurfaceEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SurfaceEntry) -> Void) {
        completion(SurfaceEntry(date: Date(), snapshot: store.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SurfaceEntry>) -> Void) {
        let now = Date()
        let entry = SurfaceEntry(date: now, snapshot: store.read())
        completion(Timeline(entries: [entry],
                            policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }
}
