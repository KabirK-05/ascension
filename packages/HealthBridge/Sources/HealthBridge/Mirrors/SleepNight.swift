import AscensionCore
import Foundation

/// One night's sleep, attributed to the morning the user woke up on (spec §6).
///
/// Keyed on that date, and carrying the HealthKit UUIDs it was built from, so rebuilding
/// the night from the same samples produces the same row.
public struct SleepNight: Hashable, Sendable, Identifiable {
    public var id: CalendarDate { date }
    public var date: CalendarDate
    public var start: Date
    public var end: Date
    public var asleepMinutes: Int
    /// `nil` when no in-bed sample exists — an Apple Watch-only night often has none,
    /// and the contract's `null` means not measured.
    public var inBedMinutes: Int?
    /// Sorted HealthKit UUID strings, the evidence this row was derived from.
    public var sourceSampleIds: [String]

    public init(date: CalendarDate, start: Date, end: Date, asleepMinutes: Int,
                inBedMinutes: Int? = nil, sourceSampleIds: [String] = []) {
        self.date = date
        self.start = start
        self.end = end
        self.asleepMinutes = asleepMinutes
        self.inBedMinutes = inBedMinutes
        self.sourceSampleIds = sourceSampleIds
    }

    /// The contract shape this mirror feeds. `consistencySd7Minutes` is a 7-day trend and
    /// belongs to the trends engine, not here.
    public var rollup: SleepRollup {
        SleepRollup(asleepMinutes: asleepMinutes, inBedMinutes: inBedMinutes)
    }
}

/// Turns sleep-analysis samples into nights.
public enum SleepNightBuilder {
    /// Samples more than this far apart belong to different sleep sessions.
    public static let defaultSessionGap: TimeInterval = 90 * 60

    /// One night per calendar day, attributed to the day the session *ended* — the
    /// morning you woke up, which is the day the Today screen asks about.
    ///
    /// Where a day holds several sessions, the longest wins and the rest are ignored: an
    /// afternoon nap is not last night's sleep, and adding it to the night would inflate
    /// the number the readiness engine reads. Durations are measured over the union of
    /// overlapping samples, never their sum.
    public static func nights(from records: [CategoryRecord],
                              timeZone: TimeZone,
                              sessionGap: TimeInterval = defaultSessionGap) -> [SleepNight] {
        let sessions = self.sessions(from: records, sessionGap: sessionGap)
        var longestPerDay: [CalendarDate: SleepNight] = [:]
        for session in sessions {
            guard let night = night(from: session, timeZone: timeZone) else { continue }
            guard let incumbent = longestPerDay[night.date] else {
                longestPerDay[night.date] = night
                continue
            }
            if night.asleepMinutes > incumbent.asleepMinutes ||
                (night.asleepMinutes == incumbent.asleepMinutes && night.start < incumbent.start) {
                longestPerDay[night.date] = night
            }
        }
        return longestPerDay.values.sorted { $0.date < $1.date }
    }

    /// Samples grouped into sessions by gap, each group in ascending order.
    public static func sessions(from records: [CategoryRecord],
                                sessionGap: TimeInterval = defaultSessionGap) -> [[CategoryRecord]] {
        let sleepRecords = MetricAggregator.deduplicatedCategories(records)
            .filter { $0.metric == .sleepAnalysis && $0.end > $0.start }
        var sessions: [[CategoryRecord]] = []
        var current: [CategoryRecord] = []
        var reach: Date?
        for record in sleepRecords {
            if let reach, record.start.timeIntervalSince(reach) > sessionGap {
                sessions.append(current)
                current = []
            }
            current.append(record)
            reach = max(reach ?? record.end, record.end)
        }
        if !current.isEmpty { sessions.append(current) }
        return sessions
    }

    private static func night(from session: [CategoryRecord], timeZone: TimeZone) -> SleepNight? {
        guard let first = session.first else { return nil }
        let end = session.map(\.end).max() ?? first.end
        guard let date = DayWindow.calendarDate(for: end, timeZone: timeZone) else { return nil }

        let asleep = IntervalMath.union(session.filter { $0.stage?.isAsleep == true }.map(\.interval))
        let awake = session.filter { $0.stage == .awake }.map(\.interval)
        let inBedSamples = session.filter { $0.stage == .inBed }.map(\.interval)
        let asleepMinutes = IntervalMath.coveredMinutes(asleep)
        guard asleepMinutes > 0 else { return nil }
        let inBed = inBedSamples.isEmpty
            ? nil
            : IntervalMath.coveredMinutes(IntervalMath.subtracting(awake, from: inBedSamples))

        return SleepNight(
            date: date,
            start: asleep.first?.start ?? first.start,
            end: asleep.last?.end ?? end,
            asleepMinutes: asleepMinutes,
            inBedMinutes: inBed,
            sourceSampleIds: session.map(\.id.uuidString).sorted())
    }

    /// Upsert on the night's date, so a second pass over the same samples changes nothing.
    public static func merging(existing: [SleepNight], incoming: [SleepNight]) -> [SleepNight] {
        var byDate: [CalendarDate: SleepNight] = [:]
        for night in existing { byDate[night.date] = night }
        for night in incoming { byDate[night.date] = night }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
