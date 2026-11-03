import Foundation

/// The `flags` document (`docs/EXPORT_SCHEMA.md` §2.3).
///
/// Read at runtime by both the app and the Worker, so launch-phase behaviour is a flag
/// flip and never a release.
public struct FlagsDocument: Codable, Hashable, Sendable {
    public var version: Int
    public var remoteBridgeEnabled: Bool
    public var museWritesEnabled: Bool
    public var museWriteMode: MuseWriteMode
    public var rawDetailSyncEnabled: Bool
    public var foundationModelsEnabled: Bool

    public init(version: Int, remoteBridgeEnabled: Bool, museWritesEnabled: Bool,
                museWriteMode: MuseWriteMode, rawDetailSyncEnabled: Bool,
                foundationModelsEnabled: Bool) {
        self.version = version
        self.remoteBridgeEnabled = remoteBridgeEnabled
        self.museWritesEnabled = museWritesEnabled
        self.museWriteMode = museWriteMode
        self.rawDetailSyncEnabled = rawDetailSyncEnabled
        self.foundationModelsEnabled = foundationModelsEnabled
    }
}
