import AscensionCore
import AscensionEngines
import Foundation

/// The snapshot the screen shows before the app shell has injected a real source.
///
/// Not a stub and not sample data: it is the honest first-launch state. The targets and
/// the program are the seed the app installs on first run (spec §2, §3), and every
/// measurement is absent, because nothing has been read from Apple Health or logged yet.
/// The screen renders that correctly — em dashes rather than zeroes, an empty grid, and
/// a readiness score the engine marks as low confidence.
///
/// `RootTabView` keeps compiling against `TodayScreen()` while HealthKit and the store
/// are wired up in their own tickets.
public struct DefaultTodayDataSource: TodayDataSource {
    private let timezone: String

    public init(timezone: String = TimeZone.current.identifier) {
        self.timezone = timezone
    }

    public func snapshot() async throws -> TodaySnapshot {
        let zone = TimeZone(identifier: timezone) ?? .gmt
        let now = Timestamp(Date(), timeZone: zone)
        let clock = EngineClock(now: now, timezone: timezone)
        return TodaySnapshot(
            clock: clock,
            goals: Seed.goalSettings,
            program: Seed.program,
            today: DayRollup(date: clock.today,
                             timezone: timezone,
                             updatedAt: now,
                             wins: Wins(session: false, protein: false,
                                        steps: false, sleep: false)))
    }
}
