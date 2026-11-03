import AscensionCore
import Foundation

/// Stream B's device half: pull the write log, apply it, ack it
/// (`docs/TECH_STACK.md` §2.3).
///
/// Three properties this type exists to hold:
///
/// 1. **Order.** Mutations are applied by `id`, ascending. Ids are ULIDs, so that is
///    chronological — "set my target to 2200" then "make it 2300" cannot land backwards.
/// 2. **Idempotence.** Every id is checked against the persisted ledger before it is
///    applied and recorded in it immediately after, so a mutation delivered twice — a
///    retried ack, a duplicated silent push — applies once.
/// 3. **Honest acks.** Only ids that actually applied are acked, and the cursor only
///    advances over acked ids. A mutation that fails stops the drain where it is rather
///    than being skipped: applying Muse's later writes over a failed earlier one would be
///    worse than waiting.
public struct MutationDrainer: Sendable {
    private let session: SyncSession
    private let endpoint: SyncEndpoint
    private let applier: MutationApplier
    private let state: any SyncStateStore
    private let clock: any SyncClock

    public init(session: SyncSession, endpoint: SyncEndpoint, applier: MutationApplier,
                state: any SyncStateStore, clock: any SyncClock) {
        self.session = session
        self.endpoint = endpoint
        self.applier = applier
        self.state = state
        self.clock = clock
    }

    /// One pass: fetch from the stored cursor, apply, ack, persist.
    @discardableResult
    public func drain() async throws -> DrainReport {
        let page = try await fetch(since: try state.load().cursor)
        return try await apply(page)
    }

    /// Applies a page that has already been fetched, for the tests and for a push payload
    /// that carried the mutation inline.
    @discardableResult
    func apply(_ page: MutationPage) async throws -> DrainReport {
        var current = try state.load()
        var applied: [String] = []
        var alreadyApplied: [String] = []
        var blocked: BlockedMutation?

        for mutation in page.ordered {
            if current.hasApplied(mutation.id) {
                alreadyApplied.append(mutation.id)
                continue
            }
            do {
                try await applier.apply(mutation)
            } catch {
                current = current.recordingFailure(mutation.id)
                try state.save(current)
                blocked = BlockedMutation(id: mutation.id, kind: mutation.kind,
                                          reason: String(describing: error),
                                          failureCount: current.failures[mutation.id] ?? 1)
                break
            }
            current = current.recordingApplied(mutation.id)
            // Persisted before the ack: the ack is what can fail, and a mutation already
            // written into Apple Health must never be applied a second time.
            try state.save(current)
            applied.append(mutation.id)
        }

        let acked = applied + alreadyApplied
        if !acked.isEmpty {
            try await ack(ids: acked.sorted())
            if let furthest = acked.max() {
                current = current.advancingCursor(to: furthest)
                try state.save(current)
            }
        }
        return DrainReport(applied: applied, alreadyApplied: alreadyApplied,
                           blockedBy: blocked, cursor: current.cursor)
    }

    private func fetch(since cursor: String?) async throws -> MutationPage {
        let request = HTTPRequest(method: .get, url: endpoint.mutations(since: cursor))
        let response = try await session.send(request)
        guard response.isSuccess else { throw response.failure() }
        return try SyncCoding.decode(MutationPage.self, from: response.body)
    }

    private func ack(ids: [String]) async throws {
        let body = try SyncCoding.encode(MutationAck(ids: ids, appliedAt: clock.timestamp))
        let request = HTTPRequest(method: .post, url: endpoint.mutationsAck,
                                  headers: ["Content-Type": "application/json"], body: body)
        let response = try await session.send(request)
        guard response.isSuccess else { throw response.failure() }
    }
}
