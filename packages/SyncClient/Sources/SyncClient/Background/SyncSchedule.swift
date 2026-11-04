import Foundation

/// The two background task identifiers, as `Project.swift` declares them in
/// `BGTaskSchedulerPermittedIdentifiers`.
///
/// An identifier absent from that list makes `BGTaskScheduler.register` throw, so these are
/// the only two available and each has one role:
///
/// - ``nightlyPush`` is a `BGProcessingTask`. It is the same identifier `ExportKit`'s
///   nightly export uses, because they are one nightly job: export the folder, then push
///   the rollups. The app shell registers that identifier **once** and runs both.
/// - ``mutationDrain`` is a `BGAppRefreshTask`, the cheap frequent wake that drains Muse's
///   write log when a silent push did not arrive.
public enum SyncTaskIdentifier {
    public static let nightlyPush = "com.kabirkumar.ascension.nightly-export"
    public static let mutationDrain = "com.kabirkumar.ascension.rollup-sync"
}

/// When the next nightly run should be asked for.
///
/// Pure and clock-injected, so the hour it picks can be asserted rather than observed. The
/// local hour is held across a DST change: the job runs at 03:00 local, not at a fixed
/// number of seconds from the last one.
public enum SyncSchedule {
    /// The hour the nightly push asks for. Late enough that the day it summarises is over,
    /// early enough that the phone is still on charge.
    public static let nightlyHour = 3

    /// The next `nightlyHour` strictly after `date`, in `timeZone`.
    public static func nextNightlyRun(after date: Date, in timeZone: TimeZone,
                                      hour: Int = nightlyHour) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let today = calendar.date(from: components) else {
            return date.addingTimeInterval(24 * 60 * 60)
        }
        if today > date { return today }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return today.addingTimeInterval(24 * 60 * 60)
        }
        return tomorrow
    }

    /// How soon the drain may run again. The system decides when it actually does; this is
    /// the floor, and it is short because Muse's writes are meant to land in seconds.
    public static let drainRefreshInterval: TimeInterval = 15 * 60
}
