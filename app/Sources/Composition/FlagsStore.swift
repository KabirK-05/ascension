import AscensionCore
import Foundation

/// The `flags` document, which has no SwiftData model to live in.
///
/// `AscensionSchema` (spec §7) holds no flags entity — flags are configuration, not health
/// data — so the shell keeps the document in `UserDefaults`. That satisfies the standing
/// rule it exists for: launch-phase behaviour is a flag flip, read at runtime by both the
/// app and the Worker, and never a release.
///
/// The seed is the value until a `set_flag` mutation or a pull of the remote document
/// replaces it, so a fresh install reads the same flags the Worker ships with.
struct FlagsStore: Sendable {
    static let key = "ascension.documents.flags"

    // `UserDefaults` is thread-safe and documented as such, but is not marked `Sendable`.
    // The alternative is `@unchecked Sendable` on this type, which would also silence a
    // real mistake in some later field — so the exception is scoped to the one property it
    // applies to, as `ExportKit`'s own defaults-backed store does.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var document: FlagsDocument {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(FlagsDocument.self, from: data) else {
            return Seed.flags
        }
        return stored
    }

    func save(_ document: FlagsDocument) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Applies one `set_flag` change, bumping the document version.
    ///
    /// Unknown keys are ignored rather than stored: the flag set is closed (§2.7), and a
    /// typo from the Worker must not become a flag the app pretends to honour.
    func apply(key: String, value: JSONValue) {
        var updated = document
        guard case .bool(let flag) = value else { return }
        switch key {
        case "remoteBridgeEnabled": updated.remoteBridgeEnabled = flag
        case "museWritesEnabled": updated.museWritesEnabled = flag
        case "rawDetailSyncEnabled": updated.rawDetailSyncEnabled = flag
        case "foundationModelsEnabled": updated.foundationModelsEnabled = flag
        default: return
        }
        updated.version += 1
        save(updated)
    }
}
