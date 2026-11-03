import AscensionCore
import Foundation

/// The body `POST /v1/ingest` takes: `{ schemaVersion, rollups }`.
///
/// `edge/src/contract.ts` normalises a bare array into this envelope, but the envelope is
/// what it parses, and sending it keeps the Worker's error paths precise
/// (`rollups.3.training.sessionPlanned` rather than a union's noise).
public struct IngestEnvelope: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var rollups: [DayRollup]

    public init(rollups: [DayRollup], schemaVersion: Int = SyncClientModule.schemaVersion) {
        self.schemaVersion = schemaVersion
        self.rollups = rollups
    }
}

/// What the Worker answers on a successful ingest.
public struct IngestReceipt: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var accepted: Int
    public var dates: [String]
    public var ingestedAt: String

    public init(schemaVersion: Int, accepted: Int, dates: [String], ingestedAt: String) {
        self.schemaVersion = schemaVersion
        self.accepted = accepted
        self.dates = dates
        self.ingestedAt = ingestedAt
    }
}

/// Every batch of one push, and what came back.
public struct IngestReport: Hashable, Sendable {
    public var receipts: [IngestReceipt]

    public init(receipts: [IngestReceipt]) {
        self.receipts = receipts
    }

    public var accepted: Int { receipts.reduce(0) { $0 + $1.accepted } }
    public var dates: [String] { receipts.flatMap(\.dates).sorted() }
}
