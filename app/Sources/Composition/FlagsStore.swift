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
    ///
    /// `museWriteMode` is the one flag that is not a boolean (`edge/src/contract.ts`), so
    /// it is read as a string and refused unless it names a mode. Before ASC-16 it was
    /// simply dropped here, which meant a `set_flag` tightening Muse's own authority
    /// changed the Worker and never reached the phone.
    func apply(key: String, value: JSONValue) {
        var updated = document
        switch (key, value) {
        case ("remoteBridgeEnabled", .bool(let flag)): updated.remoteBridgeEnabled = flag
        case ("museWritesEnabled", .bool(let flag)): updated.museWritesEnabled = flag
        case ("rawDetailSyncEnabled", .bool(let flag)): updated.rawDetailSyncEnabled = flag
        case ("foundationModelsEnabled", .bool(let flag)): updated.foundationModelsEnabled = flag
        case ("museWriteMode", .string(let raw)):
            guard let mode = MuseWriteMode(rawValue: raw) else { return }
            updated.museWriteMode = mode
        default: return
        }
        updated.version += 1
        save(updated)
    }

    /// Sets the write mode from Settings and answers with the document to push.
    ///
    /// Returned rather than pushed here: `FlagsStore` is `UserDefaults` and nothing else,
    /// and the Worker has to agree or a stale app could still be written to — the server
    /// enforces the same flag, which is the whole point of keeping launch-phase behaviour
    /// in a flag rather than in a release.
    @discardableResult
    func setMuseWriteMode(_ mode: MuseWriteMode) -> FlagsDocument {
        var updated = document
        guard updated.museWriteMode != mode else { return updated }
        updated.museWriteMode = mode
        updated.version += 1
        save(updated)
        return updated
    }
}
