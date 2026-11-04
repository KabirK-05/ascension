import AscensionCore
import Foundation

/// Stream A: the phone's one-way push of daily rollups (`docs/TECH_STACK.md` §2.3).
///
/// `POST /v1/ingest` upserts on `date`, so a repeated push is harmless by construction.
/// This client is retry-safe for the same reason and for two more of its own: a batch is
/// deduplicated by date before it is sent — the Worker rejects a batch carrying one date
/// twice, and a half-rejected batch would leave the phone unable to tell what landed — and
/// the bytes of a retry are identical to the attempt they replace, because the rollups are
/// stamped before the first send rather than per attempt.
public struct RollupPusher: Sendable {
    /// The Worker's cap, from `edge/src/http/ingest.ts`. Retention is 400 days, so a larger
    /// batch is a bug on this side rather than a backfill.
    public static let maxBatchSize = 400

    private let session: SyncSession
    private let endpoint: SyncEndpoint
    private let batchSize: Int

    public init(session: SyncSession, endpoint: SyncEndpoint,
                batchSize: Int = RollupPusher.maxBatchSize) {
        self.session = session
        self.endpoint = endpoint
        self.batchSize = min(max(1, batchSize), Self.maxBatchSize)
    }

    /// Pushes `rollups`, oldest first, in batches of at most ``maxBatchSize``.
    ///
    /// Two rollups for the same date collapse to the later `updatedAt`: they are the same
    /// day observed twice, and sending both would fail the whole batch.
    @discardableResult
    public func push(_ rollups: [DayRollup]) async throws -> IngestReport {
        let unique = Self.deduplicated(rollups)
        guard !unique.isEmpty else { return IngestReport(receipts: []) }
        var receipts: [IngestReceipt] = []
        for batch in Self.batches(of: unique, size: batchSize) {
            receipts.append(try await send(batch))
        }
        return IngestReport(receipts: receipts)
    }

    private func send(_ batch: [DayRollup]) async throws -> IngestReceipt {
        let body = try SyncCoding.encode(IngestEnvelope(rollups: batch))
        let request = HTTPRequest(method: .post, url: endpoint.ingest,
                                  headers: ["Content-Type": "application/json"], body: body)
        let response = try await session.send(request)
        guard response.isSuccess else { throw response.failure() }
        return try SyncCoding.decode(IngestReceipt.self, from: response.body)
    }

    /// One rollup per date, the newest `updatedAt` winning, oldest date first.
    static func deduplicated(_ rollups: [DayRollup]) -> [DayRollup] {
        var byDate: [CalendarDate: DayRollup] = [:]
        for rollup in rollups {
            guard let existing = byDate[rollup.date] else {
                byDate[rollup.date] = rollup
                continue
            }
            if !Self.isOlder(rollup.updatedAt, than: existing.updatedAt) {
                byDate[rollup.date] = rollup
            }
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Compared as instants, not as strings: two stamps with different UTC offsets order
    /// by the moment they name. An unparseable stamp falls back to lexicographic order.
    private static func isOlder(_ lhs: Timestamp, than rhs: Timestamp) -> Bool {
        guard let left = lhs.date, let right = rhs.date else {
            return lhs.rawValue < rhs.rawValue
        }
        return left < right
    }

    static func batches(of rollups: [DayRollup], size: Int) -> [[DayRollup]] {
        stride(from: 0, to: rollups.count, by: size).map { start in
            Array(rollups[start..<min(start + size, rollups.count)])
        }
    }
}
