import Foundation

/// The nightly auto-export schedule (spec §9.2).
///
/// The identifier matches `BGTaskSchedulerPermittedIdentifiers` in `Project.swift`.
/// `ExportKit` deliberately does not import `BackgroundTasks`: registering and
/// submitting a `BGProcessingTaskRequest` is app-lifecycle work, and keeping it out
/// here is what lets this package build and test on macOS with no simulator. The app
/// registers `NightlyExport.taskIdentifier` and calls `ExportService.runNightly`.
public enum NightlyExport {
    public static let taskIdentifier = "com.kabirkumar.ascension.nightly-export"

    /// Local hour the export aims for — late enough that the day's HealthKit data has
    /// settled, early enough to be on the user's Mac before morning.
    public static let hour = 3

    /// The next time the export should run, in the user's timezone.
    ///
    /// Computed rather than left to a plain `+24h` so the run lands at the same local
    /// hour across a daylight-saving change, which is the whole reason the app reasons
    /// in `America/Toronto` rather than in UTC.
    public static func nextRun(after date: Date, in environment: ExportEnvironment) -> Date {
        let calendar = environment.calendar
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let today = calendar.date(from: components) else {
            return date.addingTimeInterval(24 * 60 * 60)
        }
        if today > date { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(24 * 60 * 60)
    }
}
