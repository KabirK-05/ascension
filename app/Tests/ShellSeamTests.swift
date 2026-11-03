import AscensionCore
import AscensionEngines
import Foundation
import HealthBridge
import SyncClient
import Testing

@testable import Ascension

/// The seams the shell exists to close, and the date arithmetic underneath them.
@Suite("shell seams")
struct ShellSeamTests {
    private let timeZone = TimeZone(identifier: Seed.timezone) ?? .gmt

    private var clock: DayClock { DayClock(timeZone: timeZone) }

    @Test("a local day's boundaries are the user's, not UTC's")
    func dayBoundaries() {
        let date = CalendarDate.literal("2026-11-03")
        let start = clock.startOfDay(date)

        #expect(clock.day(of: start) == date)
        #expect(clock.day(of: start.addingTimeInterval(-1)) == date.adding(days: -1))
        #expect(clock.day(of: start.addingTimeInterval(23 * 3_600)) == date)
    }

    /// Midday is what a row with no recorded time is stamped with: it cannot fall into the
    /// previous or next local day however the offset shifts.
    @Test("midday stays inside its own day")
    func middayIsInsideTheDay() {
        let date = CalendarDate.literal("2026-11-01")

        #expect(clock.day(of: clock.middayOf(date)) == date)
    }

    @Test("a window of whole local days covers every day in it")
    func intervalCoversWholeDays() {
        let first = CalendarDate.literal("2026-11-01")
        let last = CalendarDate.literal("2026-11-03")
        let interval = clock.interval(from: first, through: last)

        #expect(clock.day(of: interval.start) == first)
        #expect(clock.day(of: interval.end.addingTimeInterval(-1)) == last)
    }

    /// Both Send to Watch buttons end up here, and neither may hand WorkoutKit a workout
    /// that already started.
    @Test("a session sent before the usual hour is scheduled for it")
    func watchStartTimeUsesTheUsualHour() {
        let date = CalendarDate.literal("2026-11-03")
        let morning = clock.startOfDay(date).addingTimeInterval(9 * 3_600)

        let start = WatchSessionSender.startTime(for: date, clock: clock, now: morning)

        #expect(start == clock.startOfDay(date)
            .addingTimeInterval(WatchSessionSender.defaultHour))
    }

    @Test("a session sent after the usual hour is scheduled just ahead of now")
    func watchStartTimeNeverLandsInThePast() {
        let date = CalendarDate.literal("2026-11-03")
        let evening = clock.startOfDay(date).addingTimeInterval(21 * 3_600)

        let start = WatchSessionSender.startTime(for: date, clock: clock, now: evening)

        #expect(start > evening)
        #expect(start == evening.addingTimeInterval(WatchSessionSender.minimumLead))
    }

    /// `UnavailableSessionScheduler` throws rather than quietly succeeding, and the shell
    /// must not swallow that into a success path — a Send to Watch that did nothing is
    /// worse than one that says it could not.
    @Test("with no Watch, sending refuses rather than reporting success")
    func sendingWithoutAWatchThrows() async {
        let sender = WatchSessionSender(scheduler: UnavailableSessionScheduler(), zones: nil)

        #expect(!sender.isSupported)
        await #expect(throws: SessionSchedulingError.self) {
            try await sender.send(kind: .upperA, program: Seed.program,
                                  exerciseNames: [:], clock: clock)
        }
    }

    /// A rest day has nothing to prescribe, which `SessionPlanBuilder` answers with `nil`
    /// and the shell turns into a refusal rather than an empty plan on the Watch.
    @Test("a rest day cannot be sent to the Watch")
    func restDayCannotBeSent() async {
        let sender = WatchSessionSender(scheduler: UnavailableSessionScheduler(), zones: nil)

        await #expect(throws: SessionSchedulingError.nothingToSchedule) {
            try await sender.send(kind: .rest, program: Seed.program,
                                  exerciseNames: [:], clock: clock)
        }
    }

    /// The device id is ours to mint (`docs/TECH_STACK.md` §2.6); the device token is the
    /// Worker's secret and must never be invented, because a generated one is rejected by
    /// every request.
    @Test("the device id is minted once and kept, and no token is ever invented")
    func deviceIdentityIsMintedOnce() {
        let identifiers = RecordingTokenStore()
        let identity = DeviceIdentityProvisioner.provision(
            identifiers: identifiers,
            tokens: InMemoryDeviceTokenStore(token: nil),
            mint: { "minted-id" })

        #expect(identity.deviceId == "minted-id")
        #expect(identity.isPersisted)
        #expect(!identity.canReachWorker)

        let second = DeviceIdentityProvisioner.provision(
            identifiers: identifiers,
            tokens: InMemoryDeviceTokenStore(token: nil),
            mint: { "a-different-id" })
        #expect(second.deviceId == "minted-id")
    }

    @Test("a Keychain that refuses to store the id says so rather than pretending")
    func deviceIdentityReportsAFailedStore() {
        let identity = DeviceIdentityProvisioner.provision(
            identifiers: FailingTokenStore(),
            tokens: InMemoryDeviceTokenStore(token: "a-token"),
            mint: { "minted-id" })

        #expect(identity.deviceId == "minted-id")
        #expect(!identity.isPersisted)
        #expect(identity.canReachWorker)
    }
}
