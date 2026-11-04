import AscensionCore
import Foundation
import OSLog
import SyncClient

/// Pushes a document the device changed up to the Worker.
///
/// Three things in the shell change a document locally — accepting a calorie suggestion,
/// flipping `museWriteMode`, undoing one of Muse's writes — and all three would be a lie
/// if the Worker kept the old value: the next thing Muse read would contradict the screen.
///
/// The version comes from the Worker rather than from the local copy. `PUT` is
/// `If-Match`-guarded (`docs/EXPORT_SCHEMA.md` §2), and the local version counts this
/// device's edits while the remote one counts everyone's, so sending the local number
/// would collide on every second write.
///
/// An unpaired device, an unreachable Worker or a lost race all answer `false` and change
/// nothing remotely. The local write has already happened and stands: it is the user's own
/// edit on their own phone, and refusing it because the network is down would be worse.
struct RemoteDocumentWriter: Sendable {
    private let engine: @Sendable () async -> SyncEngine?
    private let logger = Logger(subsystem: "com.kabirkumar.ascension", category: "documents")

    init(engine: @escaping @Sendable () async -> SyncEngine?) {
        self.engine = engine
    }

    /// A writer for a device that is not paired. Everything it is asked to send, it does
    /// not send, and says so.
    static let unpaired = RemoteDocumentWriter(engine: { nil })

    @discardableResult
    func write(_ document: some Encodable & Sendable, to key: SyncDocumentKey) async -> Bool {
        guard let engine = await engine() else { return false }
        do {
            let current = try await engine.document(key)
            _ = try await engine.write(document: document, to: key, ifMatch: current.version)
            return true
        } catch {
            logger.info("\(key.rawValue, privacy: .public) not pushed: \(error, privacy: .public)")
            return false
        }
    }
}
