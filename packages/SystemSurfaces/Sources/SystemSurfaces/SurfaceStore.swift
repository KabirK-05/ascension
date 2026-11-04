import AscensionCore
import Foundation

/// The app group the app and its widgets share.
///
/// A widget runs in its own process with its own container, so the only way it sees a
/// number the app measured is through here. The identifier is also in both targets'
/// entitlements; `Project.swift` is the single place it is written down for the build.
public enum AppGroup {
    public static let identifier = "group.com.kabirkumar.ascension"

    /// The shared container, or `nil` when the entitlement is missing — on a build with no
    /// provisioning profile for the group, for instance. A `nil` here is why
    /// ``SurfaceStore`` reads and writes nothing rather than trapping.
    public static func containerURL(
        fileManager: FileManager = .default,
        identifier: String = AppGroup.identifier
    ) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Reads and writes the one ``SurfaceSnapshot`` in the shared container.
///
/// A file rather than `UserDefaults(suiteName:)`: this is a document, it is written
/// atomically, and a half-written snapshot that a widget reads mid-refresh would draw a
/// number from two different days.
///
/// Every failure is silent and total — no snapshot, rather than a wrong one. A widget with
/// nothing to draw shows its placeholder, which is correct; a widget drawing a stale
/// number as if it were today's is not.
public struct SurfaceStore: Sendable {
    public static let fileName = "surface.json"

    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    /// The shared container's snapshot file. `nil` container means a store that answers
    /// `nil` to everything, which is exactly how an unentitled build should behave.
    public init(group: String = AppGroup.identifier, fileManager: FileManager = .default) {
        self.init(url: AppGroup.containerURL(fileManager: fileManager, identifier: group)?
            .appending(path: Self.fileName))
    }

    public func read() -> SurfaceSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder().decode(SurfaceSnapshot.self, from: data)
    }

    /// Writes atomically, so a widget mid-read sees either the old snapshot or the new one.
    @discardableResult
    public func write(_ snapshot: SurfaceSnapshot) -> Bool {
        guard let url, let data = try? Self.encoder().encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// ISO-8601 dates in, ISO-8601 dates out — the same shape as every other document the
    /// project writes (`docs/EXPORT_SCHEMA.md`), so the file is readable by eye.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
