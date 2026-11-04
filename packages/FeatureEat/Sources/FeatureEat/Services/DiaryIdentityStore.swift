import Foundation
import SwiftData

/// The stable identity of a diary row, kept outside `MealLog`.
///
/// **Why this exists at all.** `MealLog` (spec §7, owned by `AscensionCore`) stores the
/// day, the meal, the portion and the macros — no row id and no time of day.
/// `SwiftDataMealDiaryStore` therefore minted an id per launch and held it in a
/// dictionary, which was fine while nothing downstream depended on it.
///
/// ASC-24 made it depend on it. A row's id is what `HealthWriter` turns into the
/// HealthKit sync identifier, so an id that changes at launch means the samples a meal
/// wrote on Monday can no longer be found on Tuesday: deleting that meal takes it out of
/// the diary and leaves its calories in Apple Health forever. That is the phantom-calorie
/// half of "the eat flow doesn't work properly".
///
/// So the mapping is persisted beside the store rather than inside it. A JSON file in
/// Application Support, keyed by the row id, holding SwiftData's own
/// `PersistentIdentifier` for the `MealLog` and the instant the row was logged — which
/// also fixes the second half of the old comment, that rows from an earlier session
/// sorted by name because their time of day had been forgotten.
struct DiaryIdentityRecord: Codable, Hashable, Sendable {
    var model: PersistentIdentifier
    var loggedAt: Date
    /// Where the row stands with Apple Health. Decoded leniently so a file written
    /// before this field existed still loads, with the honest answer for a row nothing
    /// recorded: it is not known to be in Health.
    var healthWrite: HealthWriteState = .notWritten

    init(model: PersistentIdentifier, loggedAt: Date,
         healthWrite: HealthWriteState = .notWritten) {
        self.model = model
        self.loggedAt = loggedAt
        self.healthWrite = healthWrite
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(PersistentIdentifier.self, forKey: .model)
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
        healthWrite = try container.decodeIfPresent(HealthWriteState.self,
                                                    forKey: .healthWrite) ?? .notWritten
    }
}

/// Where the identity map lives. Behind a protocol so the SwiftData store is testable
/// without a filesystem, and so a preview cannot write to the user's disk.
protocol DiaryIdentityStore: Sendable {
    func load() -> [String: DiaryIdentityRecord]
    func save(_ records: [String: DiaryIdentityRecord])
}

/// A JSON file in Application Support.
///
/// Written atomically, and a write that fails is swallowed: a diary row the app can
/// still see and still delete *this session* is better than a crash, and the next
/// successful write repairs the file.
struct FileDiaryIdentityStore: DiaryIdentityStore {
    private let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
            return
        }
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL.temporaryDirectory
        let folder = base.appending(path: "Ascension", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.url = folder.appending(path: "diary-identity.json")
    }

    func load() -> [String: DiaryIdentityRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: DiaryIdentityRecord].self, from: data)) ?? [:]
    }

    func save(_ records: [String: DiaryIdentityRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// An identity map with no file behind it, for previews and tests.
final class MemoryDiaryIdentityStore: DiaryIdentityStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: DiaryIdentityRecord]

    init(records: [String: DiaryIdentityRecord] = [:]) {
        self.records = records
    }

    func load() -> [String: DiaryIdentityRecord] { lock.withLock { records } }

    func save(_ records: [String: DiaryIdentityRecord]) {
        lock.withLock { self.records = records }
    }
}
