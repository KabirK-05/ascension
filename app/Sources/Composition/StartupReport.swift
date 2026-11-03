import Foundation
import OSLog

/// What the app actually managed to wire at launch.
///
/// Every field is something that can genuinely be unavailable on a real device: no
/// Keychain, no export folder chosen, no Watch, no pairing with the Worker. Collected in
/// one value and logged once, because the alternative is a build that looks identical
/// whether or not half of it is connected — and `docs/DESIGN_RULES.md` §1 rules out
/// explaining any of it on screen.
struct StartupReport: Sendable, Hashable {
    var storeIsPersistent: Bool
    var seedInstalled: Bool
    var deviceIdIsPersistent: Bool
    var remote: String
    var watchScheduling: Bool
    var exportDestinationChosen: Bool
    var heartRateMaximumKnown: Bool
    var syncStateIsPersistent: Bool

    /// Short, factual lines. Read in Console, not on a screen.
    var lines: [String] {
        [
            "store: \(storeIsPersistent ? "on disk" : "in memory")",
            "seed: \(seedInstalled ? "installed or already present" : "failed")",
            "deviceId: \(deviceIdIsPersistent ? "keychain" : "this launch only")",
            "worker: \(remote)",
            "sync state: \(syncStateIsPersistent ? "on disk" : "in memory")",
            "watch: \(watchScheduling ? "schedulable" : "unavailable")",
            "export folder: \(exportDestinationChosen ? "chosen" : "not chosen")",
            "max heart rate: \(heartRateMaximumKnown ? "set" : "unset, zones off")"
        ]
    }

    func log(to logger: Logger = Logger(subsystem: "com.kabirkumar.ascension",
                                        category: "startup")) {
        for line in lines {
            logger.info("\(line, privacy: .public)")
        }
    }
}
