import Foundation

/// When the Worker last accepted a push, and when a drain last ran.
///
/// Settings has to answer "is this actually working?" without a sentence, and the only
/// honest answer is a time. `SyncEngine` reports a receipt per call and remembers nothing
/// across launches, so the shell records the two instants here.
///
/// `UserDefaults` rather than the ledger: these are facts about the connection, not about
/// a day, and a background wake has to be able to write them while the device is locked.
struct SyncActivity: Sendable {
    static let lastPushKey = "ascension.sync.lastPushAt"
    static let lastDrainKey = "ascension.sync.lastDrainAt"

    // Thread-safe and documented as such, but not marked `Sendable` — scoped here exactly
    // as `FlagsStore` does, rather than making the whole type unchecked.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastPushAt: Date? { defaults.object(forKey: Self.lastPushKey) as? Date }
    var lastDrainAt: Date? { defaults.object(forKey: Self.lastDrainKey) as? Date }

    func recordPush(at instant: Date = Date()) {
        defaults.set(instant, forKey: Self.lastPushKey)
    }

    func recordDrain(at instant: Date = Date()) {
        defaults.set(instant, forKey: Self.lastDrainKey)
    }
}
