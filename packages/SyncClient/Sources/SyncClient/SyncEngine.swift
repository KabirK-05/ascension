import AscensionCore
import Foundation

/// Everything the app shell needs, assembled once.
///
/// An actor because the three callers — foreground, `BGAppRefreshTask` and a silent push —
/// can arrive at the same moment, and a drain running twice over one page would ask the
/// applier to do the same work concurrently. Serialising here means the ledger is read and
/// written by one task at a time.
public actor SyncEngine {
    private let pusher: RollupPusher
    private let drainer: MutationDrainer
    private let documents: DocumentClient

    public init(pusher: RollupPusher, drainer: MutationDrainer, documents: DocumentClient) {
        self.pusher = pusher
        self.drainer = drainer
        self.documents = documents
    }

    /// The usual wiring, from a Worker origin and a Keychain-backed token.
    public static func live(origin: SyncEndpoint,
                            tokens: any DeviceTokenStore,
                            local: any LocalStateApplier,
                            health: any HealthWriteBack,
                            state: any SyncStateStore,
                            clock: any SyncClock = SystemClock(),
                            transport: any HTTPTransport = URLSessionTransport(),
                            policy: RetryPolicy = RetryPolicy()) -> SyncEngine {
        let session = SyncSession(transport: transport, tokens: tokens, policy: policy)
        let applier = MutationApplier(local: local, health: health, clock: clock)
        return SyncEngine(
            pusher: RollupPusher(session: session, endpoint: origin),
            drainer: MutationDrainer(session: session, endpoint: origin, applier: applier,
                                     state: state, clock: clock),
            documents: DocumentClient(session: session, endpoint: origin, clock: clock))
    }

    @discardableResult
    public func push(_ rollups: [DayRollup]) async throws -> IngestReport {
        try await pusher.push(rollups)
    }

    @discardableResult
    public func drain() async throws -> DrainReport {
        try await drainer.drain()
    }

    public func document(_ key: SyncDocumentKey) async throws -> RemoteDocument {
        try await documents.fetch(key)
    }

    @discardableResult
    public func write(document: some Encodable & Sendable, to key: SyncDocumentKey,
                      ifMatch version: Int,
                      localUpdatedAt: Timestamp? = nil) async throws -> DocumentWriteResult {
        try await documents.write(document: document, to: key, ifMatch: version,
                                  localUpdatedAt: localUpdatedAt)
    }

    /// Drain first, then push.
    ///
    /// That order is deliberate: a queued `log_meal` becomes part of today's rollup, so
    /// applying before pushing sends one rollup that already has it rather than two.
    ///
    /// Both halves are attempted even if the first fails — a drain blocked on one bad
    /// mutation must not also stop the day's observations reaching the cloud — and the
    /// first error is rethrown once both have run.
    @discardableResult
    public func syncNow(rollups: [DayRollup]) async throws -> SyncOutcome {
        var failure: (any Error)?
        var report: DrainReport?
        do {
            report = try await drainer.drain()
        } catch {
            failure = error
        }
        var receipt: IngestReport?
        do {
            receipt = try await pusher.push(rollups)
        } catch {
            failure = failure ?? error
        }
        if let failure { throw failure }
        return SyncOutcome(drain: report, ingest: receipt)
    }
}

/// What a full sync did.
public struct SyncOutcome: Hashable, Sendable {
    public var drain: DrainReport?
    public var ingest: IngestReport?

    public init(drain: DrainReport?, ingest: IngestReport?) {
        self.drain = drain
        self.ingest = ingest
    }

    /// True when something was applied or accepted, which is what a background task reports
    /// back to the system as `setTaskCompleted(success:)`.
    public var didChangeAnything: Bool {
        (drain?.didApplyAnything ?? false) || (ingest?.accepted ?? 0) > 0
    }
}
