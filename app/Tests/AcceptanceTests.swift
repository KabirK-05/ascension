import AscensionCore
import ExportKit
import Foundation
import HealthBridge
import SwiftData
import SyncClient
import Testing

@testable import Ascension

/// ASC-18 — the spec's acceptance run (§9.3), device half.
///
/// `edge/test/acceptance.test.ts` is the other half: it drives the Worker's MCP surface
/// as a real connector — OAuth, PKCE, Streamable HTTP — asks "how is my training going
/// this month?", changes a calorie target, swaps a session and queues a meal. It cannot
/// go further, because the last link in the chain is HealthKit and HealthKit can only be
/// written from the device.
///
/// This is that last link. The two suites meet at `edge/test/golden/mutations.page.json`:
/// the cloud half asserts the Worker produces exactly that page, and this one replays it
/// through the real `MutationDrainer`, the real `MutationApplier`, the shell's own
/// `StoreMutationApplier` and `HealthMutationWriteBack`, into `FakeHealthStore`. Nothing
/// here is hand-built from a Swift literal; if the Worker renames a field, the golden
/// changes and this suite stops decoding it.
@Suite("ASC-18 — the acceptance run, device half")
@MainActor
struct AcceptanceTests {
    /// The three ids in the golden page, in the order a ULID sort puts them.
    private static let targetsId = "01MACCEPTANCE0000000000001"
    private static let scheduleId = "01MACCEPTANCE0000000000002"
    private static let mealId = "01MACCEPTANCE0000000000003"

    private static let mealDay = CalendarDate.literal("2026-10-31")
    private static let userTimeZone = TimeZone(identifier: Seed.timezone) ?? .gmt

    // MARK: - The device, assembled

    private struct Device {
        let store: LocalStore
        let health: FakeHealthStore
        let scheduler: RecordingSessionScheduler
        let transport: ReplayTransport
        let state: InMemorySyncStateStore
        let changes: ChangeLog
        let drainer: MutationDrainer
    }

    /// Everything the composition root wires for Stream B, with HealthKit and the Watch
    /// replaced by fakes and nothing else changed.
    private func device(page: Data = AcceptanceGolden.pageBytes,
                        authorizeNutrition: Bool = true) throws -> Device {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AscensionSchema.schema,
                                           configurations: configuration)
        let store = LocalStore(container: container)
        #expect(store.installSeed())

        let health = FakeHealthStore()
        if authorizeNutrition {
            for metric in [HealthWriteMetric.dietaryEnergy, .dietaryProtein,
                           .dietaryCarbohydrates, .dietaryFat, .dietaryWater] {
                health.allow(metric)
            }
        }

        let scheduler = RecordingSessionScheduler()
        let changes = ChangeLog(url: FileManager.default.temporaryDirectory
            .appending(path: "acceptance-changes-\(UUID().uuidString).json"))
        let local = StoreMutationApplier(
            store: store,
            flags: FlagsStore(defaults: UserDefaults(
                suiteName: "ascension.tests.acceptance.\(UUID().uuidString)") ?? .standard),
            watch: WatchSessionSender(scheduler: scheduler, zones: nil),
            export: ExportRunnerStub.unavailable(store: store),
            changes: changes,
            now: { HealthDates.fixedNow })

        let clock = try #require(
            FixedClock(timestamp: Timestamp.literal("2026-10-31T20:15:00-04:00")))
        let transport = ReplayTransport(page: page)
        let state = InMemorySyncStateStore()
        let drainer = MutationDrainer(
            session: SyncSession(transport: transport,
                                 tokens: RecordingTokenStore(token: "device-token"),
                                 sleeper: NoSleep()),
            endpoint: try #require(SyncEndpoint(origin: "https://edge.invalid")),
            applier: MutationApplier(
                local: local,
                health: HealthMutationWriteBack(writer: HealthWriter(store: health)),
                clock: clock),
            state: state,
            clock: clock)

        return Device(store: store, health: health, scheduler: scheduler,
                      transport: transport, state: state, changes: changes, drainer: drainer)
    }

    // MARK: - The golden page is the Worker's, not this test's

    @Test("the golden page the cloud half froze is the one being replayed")
    func goldenPageIsTheContract() throws {
        let page: MutationPage = try JSONDecoder().decode(MutationPage.self,
                                                          from: AcceptanceGolden.pageBytes)
        #expect(page.schemaVersion == 1)
        #expect(page.cursor == Self.mealId)
        #expect(page.ordered.map(\.id) == [Self.targetsId, Self.scheduleId, Self.mealId])
        #expect(page.ordered.map(\.kind) == [.setTargets, .scheduleWorkout, .logMeal])
        // Tier 1 was applied in the cloud; Tier 2 is still waiting for this device.
        #expect(page.ordered[0].isApplied)
        #expect(!page.ordered[1].isApplied)
        #expect(!page.ordered[2].isApplied)
        #expect(page.ordered.allSatisfy { $0.actor == .muse })
    }

    /// Chicken and eggs are the only meats (CLAUDE.md, spec §2). A fixture that broke it
    /// would be the one place the rule could reach real HealthKit samples.
    @Test("nothing in the page Muse sent is pork or beef")
    func theMealObeysTheDietaryRule() throws {
        let text = try #require(String(bytes: AcceptanceGolden.pageBytes, encoding: .utf8))
            .lowercased()
        for forbidden in ["pork", "beef", "bacon", "ham", "steak", "mutton", "lamb"] {
            #expect(!text.contains(forbidden), "the acceptance meal must not contain \(forbidden)")
        }
        #expect(text.contains("chicken"))
        #expect(text.contains("eggs"))
    }

    // MARK: - One drain, the whole of Stream B's device half

    @Test("one drain applies all three of Muse's writes, in ULID order")
    func drainAppliesEverything() async throws {
        let device = try device()

        let report = try await device.drainer.drain()

        #expect(report.applied == [Self.targetsId, Self.scheduleId, Self.mealId])
        #expect(report.blockedBy == nil)
        #expect(report.cursor == Self.mealId)
    }

    @Test("the calorie target Muse set in the cloud reaches the device's own copy")
    func targetsReachTheStore() async throws {
        let device = try device()
        let before = device.store.goals

        try await device.drainer.drain()

        let goals = device.store.goals
        #expect(goals.targets.kcal == 2400)
        #expect(goals.targets.proteinG == 165)
        #expect(goals.version == before.version + 1)
        #expect(goals.updatedBy == .muse)
        // The invariants the Worker enforces are enforced here too, on the merged document.
        #expect(goals.targets.fatMinG >= 60)
        #expect((1400...4000).contains(goals.targets.kcal))
        #expect(goals.targets.proteinMinG <= goals.targets.proteinG)
    }

    @Test("the swapped session reaches the Watch as a plan, never as a recording")
    func theSwapReachesTheWatch() async throws {
        let device = try device()

        try await device.drainer.drain()

        #expect(device.scheduler.scheduled.count == 1)
        let sent = try #require(device.scheduler.scheduled.first)
        // "Lower B" is the name the seeded program gives `lowerB`, and the plan carries
        // its exercises: the swap sent the session, not just its name.
        #expect(sent.plan.displayName.contains("Lower B"))
        #expect(sent.plan.activity == .traditionalStrengthTraining)
        #expect(!sent.plan.blocks.isEmpty)
        // Scheduled inside the day Muse asked for, in the user's own timezone.
        #expect(DayClock(timeZone: Self.userTimeZone).day(of: sent.date) == Self.mealDay)
    }

    /// The point of the whole ticket: a meal Muse logged with no app open ends up in
    /// Apple Health, because the phone — and only the phone — can put it there.
    @Test("the queued meal lands in Apple Health with the macros Muse sent")
    func theMealLandsInAppleHealth() async throws {
        let device = try device()

        try await device.drainer.drain()

        let samples = device.health.savedSamples
        let byMetric = Dictionary(grouping: samples, by: \.metric)
            .compactMapValues { $0.reduce(0) { $0 + $1.value } }

        // 330 + 155 kcal, 62 + 13 g protein, 7 + 11 g fat, 0 + 1 g carbohydrate.
        #expect(byMetric[.dietaryEnergy] == 485)
        #expect(byMetric[.dietaryProtein] == 75)
        #expect(byMetric[.dietaryFat] == 18)
        #expect(byMetric[.dietaryCarbohydrates] == 1)
        // No water in a `log_meal`: F4 owns water, and this payload carried none.
        #expect(byMetric[.dietaryWater] == nil)

        // The mutation's ULID is the sample identity, which is what stops a redelivery
        // becoming a second lunch.
        #expect(samples.allSatisfy { $0.syncIdentifier.contains(Self.mealId) })

        // Lunch is stamped at 13:00 in the user's own day, not at the drain's instant.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.userTimeZone
        let hours = Set(samples.map { calendar.component(.hour, from: $0.start) })
        #expect(hours == [13])
        let days = Set(samples.map { DayClock(timeZone: Self.userTimeZone).day(of: $0.start) })
        #expect(days == [Self.mealDay])
    }

    @Test("the same meal is also one diary row per food, so the day's totals include it")
    func theMealLandsInTheDiary() async throws {
        let device = try device()

        try await device.drainer.drain()

        let rows = device.store.mealLogs(on: Self.mealDay)
        #expect(rows.count == 2)
        #expect(rows.map(\.foodName).sorted() == ["Chicken breast", "Two eggs, boiled"])
        #expect(rows.reduce(0) { $0 + $1.kcal } == 485)
    }

    @Test("every write Muse made is listed in Settings → Changes")
    func everyWriteIsAuditable() async throws {
        let device = try device()

        try await device.drainer.drain()

        let recorded = await device.changes.all()
        #expect(Set(recorded.map(\.id)) == [Self.targetsId, Self.scheduleId, Self.mealId])
        #expect(Set(recorded.map(\.kind)) == [.setTargets, .scheduleWorkout, .logMeal])
        // The targets change is the one that can be undone: it carries what it replaced.
        let targets = try #require(recorded.first { $0.id == Self.targetsId })
        #expect(targets.previous != nil)
    }

    @Test("the device acks exactly what it applied, and advances the cursor")
    func theAckIsHonest() async throws {
        let device = try device()

        try await device.drainer.drain()

        let acks = device.transport.requests.filter { $0.url.path.hasSuffix("/mutations/ack") }
        #expect(acks.count == 1)
        let body = try #require(acks.first?.body)
        let ack = try JSONDecoder().decode(MutationAck.self, from: body)
        #expect(ack.ids == [Self.targetsId, Self.scheduleId, Self.mealId])
        #expect(ack.schemaVersion == 1)
        #expect(try device.state.load().cursor == Self.mealId)
    }

    /// The ack can fail after the HealthKit write succeeded, so the Worker redelivers.
    /// A second lunch in Apple Health would be the worst outcome in the whole loop.
    @Test("the same page delivered twice writes the meal once")
    func aRedeliveredPageIsANoOp() async throws {
        let device = try device()

        try await device.drainer.drain()
        let afterFirst = device.health.savedSamples.count
        let report = try await device.drainer.drain()

        #expect(report.applied.isEmpty)
        #expect(report.alreadyApplied == [Self.targetsId, Self.scheduleId, Self.mealId])
        #expect(device.health.savedSamples.count == afterFirst)
        #expect(device.store.mealLogs(on: Self.mealDay).count == 2)
        #expect(device.store.goals.targets.kcal == 2400)
    }

    /// A poison pill must stop the drain where it is rather than letting Muse's later
    /// writes land over a failed earlier one. The Watch is the easiest link to break.
    @Test("a session the Watch refuses blocks the drain, and the meal stays queued")
    func aFailedSwapBlocksTheDrain() async throws {
        let device = try device()
        device.scheduler.failNext = true

        let report = try await device.drainer.drain()

        #expect(report.applied == [Self.targetsId])
        #expect(report.blockedBy?.id == Self.scheduleId)
        #expect(report.blockedBy?.kind == .scheduleWorkout)
        #expect(device.health.savedSamples.isEmpty)
        #expect(device.store.mealLogs(on: Self.mealDay).isEmpty)

        let acks = device.transport.requests.filter { $0.url.path.hasSuffix("/mutations/ack") }
        let ack = try JSONDecoder().decode(MutationAck.self, from: #require(acks.first?.body))
        #expect(ack.ids == [Self.targetsId])
    }

    /// ASC-18 found this one and left it; ASC-27 fixed it, and this is the same scenario
    /// asserting the opposite.
    ///
    /// `HealthWriter` reports an unauthorised metric in its receipt rather than throwing —
    /// right for `FeatureEat`, where the row is kept out of the diary when nothing reached
    /// Health — and `HealthMutationWriteBack` used to discard that receipt, so a meal Muse
    /// logged while the nutrition scopes were refused became a local-only total, was acked,
    /// and was never retried. HealthKit is the source of truth (spec §3), so that was
    /// silent divergence: the app held a meal Apple Health had never seen.
    ///
    /// Now the whole real stack — `HealthWriter`, the shell's `HealthMutationWriteBack`,
    /// `MutationApplier`, `MutationDrainer` — refuses to call it applied.
    @Test("a meal Apple Health refused is not acked, and does not reach the diary")
    func aRefusedScopeIsNotAcked() async throws {
        let device = try device(authorizeNutrition: false)

        let report = try await device.drainer.drain()

        // The meal did not apply, and it blocked the drain where it stands rather than
        // being skipped, so the Worker will deliver it again.
        #expect(!report.applied.contains(Self.mealId))
        #expect(report.blockedBy?.id == Self.mealId)
        #expect(report.blockedBy?.kind == .logMeal)
        #expect(device.health.savedSamples.isEmpty)
        // Nothing on the day. The applied run writes Muse's two items — chicken breast and
        // two boiled eggs — and a refused write must leave the diary claiming none of it.
        #expect(device.store.mealLogs(on: Self.mealDay).isEmpty)

        let acks = device.transport.requests.filter { $0.url.path.hasSuffix("/mutations/ack") }
        let acked = try acks.compactMap(\.body)
            .flatMap { try JSONDecoder().decode(MutationAck.self, from: $0).ids }
        #expect(!acked.contains(Self.mealId))
    }

    /// The other half of the fix, end to end: a scope refused for good cannot block Muse's
    /// write channel forever, so the drain gives up at
    /// ``MutationApplier/healthWriteAttemptLimit`` and tells the user instead.
    ///
    /// Still no diary row. The acked mutation leaves a line in Settings → Changes saying
    /// Apple Health refused it, which is the one thing that can prompt the one action — a
    /// scope only the user can grant — that would have made the meal real.
    @Test("after three refusals the meal is acked as a visible failure, not as a meal")
    func aPermanentRefusalBecomesAVisibleFailure() async throws {
        let device = try device(authorizeNutrition: false)

        for _ in 1...2 { _ = try? await device.drainer.drain() }
        let final = try await device.drainer.drain()

        #expect(final.applied.contains(Self.mealId))
        #expect(final.blockedBy == nil)
        #expect(device.health.savedSamples.isEmpty)
        #expect(device.store.mealLogs(on: Self.mealDay).isEmpty)

        let row = try #require(await device.changes.change(id: Self.mealId))
        #expect(row.kind == .logMeal)
        #expect(row.summary.contains("Health refused"))
        #expect(!row.canUndo)
    }
}

// MARK: - Support

/// The golden page `edge/test/acceptance.test.ts` asserts the Worker produces.
///
/// Read off disk rather than embedded, so the two halves cannot drift: there is one file,
/// the cloud half compares the live `GET /v1/mutations` against it, and this half decodes
/// it with the app's own `Codable` types.
enum AcceptanceGolden {
    static let url: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // app/Tests
        .deletingLastPathComponent()   // app
        .deletingLastPathComponent()   // <repo>
        .appending(path: "edge/test/golden/mutations.page.json")

    static let pageBytes: Data = {
        guard let data = try? Data(contentsOf: url) else {
            fatalError("the acceptance golden is missing at \(url.path) — "
                       + "edge/test/acceptance.test.ts writes the contract this replays")
        }
        return data
    }()
}

/// A transport that answers the drain's `GET` with the golden page and records the ack.
final class ReplayTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let page: Data
    private var recorded: [HTTPRequest] = []

    init(page: Data) {
        self.page = page
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        let body = request.url.path.hasSuffix("/mutations/ack") ? Data("{}".utf8) : page
        return HTTPResponse(status: 200,
                            headers: ["Content-Type": "application/json"],
                            body: body)
    }
}

/// A Watch that is there, records what it was handed, and can be made to refuse.
final class RecordingSessionScheduler: SessionScheduling, @unchecked Sendable {
    struct Sent: Sendable {
        let plan: SessionPlan
        let date: Date
    }

    private let lock = NSLock()
    private var plans: [Sent] = []
    private var shouldFail = false

    var isSupported: Bool { true }

    var failNext: Bool {
        get { lock.withLock { shouldFail } }
        set { lock.withLock { shouldFail = newValue } }
    }

    var scheduled: [Sent] { lock.withLock { plans } }

    func requestAuthorization() async -> SessionSchedulingAuthorization { .authorized }

    func schedule(_ plan: SessionPlan, at date: Date) async throws {
        if lock.withLock({ shouldFail }) { throw SessionSchedulingError.nothingToSchedule }
        lock.withLock { plans.append(Sent(plan: plan, date: date)) }
    }

    func removeScheduled() async {
        lock.withLock { plans.removeAll() }
    }
}

/// Backoff with no wall-clock cost: the drain's retry policy is not what is under test.
struct NoSleep: Sleeper {
    func sleep(for duration: Duration) async throws {}
}
