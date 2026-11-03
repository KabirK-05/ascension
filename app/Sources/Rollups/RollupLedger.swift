import AscensionCore
import AscensionEngines
import Foundation

/// Every `DayRollup` the device has assembled, plus which of them the Worker has not seen.
///
/// **Why the shell owns this at all.** `AscensionSchema` has no rollup entity — rollups are
/// a projection, not a stored model — so before this ticket nothing in the app remembered a
/// day once it had been drawn. That is fine for today, and wrong for everything else: the
/// consistency grid reads 119 days (`TodaySnapshot.historyDays`), readiness averages 30,
/// the trends engines read 28, the export writes the lot, and HealthKit can only be asked
/// one day at a time through `HealthStore.statistic(_:in:)`. Re-deriving a year of days on
/// every tab load is not an option, so the shell assembles a short trailing window each
/// refresh and accumulates the answers here.
///
/// A pure value type: merging, pending-push bookkeeping and retention are all decisions
/// worth testing without a filesystem. ``RollupStore`` is the actor that persists it.
struct RollupLedger: Codable, Hashable, Sendable {
    /// Rolling retention, matching `docs/TECH_STACK.md` §2.6.
    static let retentionDays = 400

    /// Keyed by `CalendarDate.rawValue`, which is also how the Worker keys `/v1/ingest`.
    private(set) var days: [String: DayRollup]

    /// Dates assembled since the last successful push. Not derived from `updatedAt`:
    /// re-assembling an unchanged day stamps a fresh `updatedAt`, so a timestamp
    /// comparison would mark every day pending forever.
    private(set) var pendingDates: Set<String>

    init(days: [String: DayRollup] = [:], pendingDates: Set<String> = []) {
        self.days = days
        self.pendingDates = pendingDates
    }

    /// Every day held, earliest first.
    var all: [DayRollup] {
        days.values.sorted { $0.date < $1.date }
    }

    func rollup(on date: CalendarDate) -> DayRollup? {
        days[date.rawValue]
    }

    /// The days the Worker has not been sent, earliest first — `RollupSource`'s answer.
    var pending: [DayRollup] {
        pendingDates
            .compactMap { days[$0] }
            .sorted { $0.date < $1.date }
    }

    /// Days in the trailing `count`-day window ending at `asOf`, earliest first.
    func history(endingOn asOf: CalendarDate, days count: Int) -> [DayRollup] {
        let window = Set(asOf.trailingWindow(days: max(1, count)).map(\.rawValue))
        return days
            .filter { window.contains($0.key) }
            .values
            .sorted { $0.date < $1.date }
    }

    /// Takes `incoming` as the newer truth for the dates it covers.
    ///
    /// A date is marked pending only when its **content** changed, `updatedAt` excluded:
    /// a refresh that re-reads the same HealthKit samples must not queue another push.
    mutating func merge(_ incoming: [DayRollup]) {
        for rollup in incoming {
            let key = rollup.date.rawValue
            if let existing = days[key], Self.isUnchanged(rollup, from: existing) {
                days[key] = existing
                continue
            }
            days[key] = rollup
            pendingDates.insert(key)
        }
    }

    /// Clears the pending mark for the dates just accepted by `/v1/ingest`.
    ///
    /// Keyed by date rather than by a receipt count so a partial push is honest: the days
    /// that landed stop being pending and the rest stay queued.
    mutating func markPushed(_ pushed: [DayRollup]) {
        for rollup in pushed {
            pendingDates.remove(rollup.date.rawValue)
        }
    }

    /// Drops days older than ``retentionDays`` before `asOf`, and any pending mark for a
    /// date that no longer has a rollup.
    mutating func prune(asOf: CalendarDate, retention: Int = retentionDays) {
        let oldest = asOf.adding(days: -max(1, retention))
        days = days.filter { _, rollup in rollup.date >= oldest }
        pendingDates = pendingDates.filter { days[$0] != nil }
    }

    /// Whether two rollups say the same thing. `updatedAt` is the clock, not a measurement.
    static func isUnchanged(_ incoming: DayRollup, from existing: DayRollup) -> Bool {
        var normalised = incoming
        normalised.updatedAt = existing.updatedAt
        return normalised == existing
    }
}
