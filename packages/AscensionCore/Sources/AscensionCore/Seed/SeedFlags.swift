import Foundation

extension Seed {
    /// Launch-phase defaults. The bridge and Muse's writes stay off until the user turns
    /// them on, and raw detail never leaves the device by default.
    public static let flags = FlagsDocument(
        version: 1,
        remoteBridgeEnabled: false,
        museWritesEnabled: false,
        museWriteMode: .propose,
        rawDetailSyncEnabled: false,
        foundationModelsEnabled: true)
}
