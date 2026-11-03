import AscensionCore
import Foundation

@testable import SyncClient

extension Fixture {
    static func documentClient(_ transport: FakeTransport,
                               maxAttempts: Int = DocumentClient.defaultMaxAttempts)
        -> DocumentClient {
        DocumentClient(session: session(transport), endpoint: origin, clock: clock,
                       maxAttempts: maxAttempts)
    }

    /// A `flags` document as the Worker serves it: the body, plus the three envelope
    /// columns and the `schemaVersion` every response carries.
    static func flagsResponse(version: Int, updatedAt: String, updatedBy: String = "muse",
                              museWritesEnabled: Bool = true,
                              museWriteMode: String = "apply",
                              rawDetailSyncEnabled: Bool = false) -> String {
        """
        {"schemaVersion":1,"version":\(version),"updatedAt":"\(updatedAt)",\
        "updatedBy":"\(updatedBy)","remoteBridgeEnabled":true,\
        "museWritesEnabled":\(museWritesEnabled),"museWriteMode":"\(museWriteMode)",\
        "rawDetailSyncEnabled":\(rawDetailSyncEnabled),"foundationModelsEnabled":true}
        """
    }

    static var flags: FlagsDocument {
        FlagsDocument(version: 2, remoteBridgeEnabled: true, museWritesEnabled: true,
                      museWriteMode: .apply, rawDetailSyncEnabled: false,
                      foundationModelsEnabled: true)
    }
}
