import AscensionCore
import Foundation
import Observation
import SyncClient

/// What the Settings screen reads and writes.
///
/// Settings is the one screen that changes how the app is wired rather than what it shows,
/// so every write here goes through the composition root and then rebuilds it: pairing the
/// device has to start the bridge now, not on the next cold launch.
@MainActor
@Observable
final class SettingsModel {

    /// The bridge, in one word. Facts only — `docs/DESIGN_RULES.md` §1.1 leaves no room
    /// for a sentence explaining what "Off" means.
    enum Bridge: String {
        case paired = "Paired"
        case noToken = "No token"
        case noOrigin = "No origin"
        case off = "Off"
    }

    var origin: String
    private(set) var maskedToken: String?
    private(set) var bridge: Bridge = .off
    private(set) var lastPush: Date?
    private(set) var exportFolderChosen: Bool
    var writeMode: MuseWriteMode
    private(set) var isSyncing = false

    private let composition: AppComposition
    private let settings: RemoteSettings

    init(composition: AppComposition) {
        self.composition = composition
        self.settings = composition.settings
        self.origin = composition.settings.origin
        self.maskedToken = composition.settings.maskedToken
        self.exportFolderChosen = composition.export.hasDestination
        self.writeMode = composition.flags.document.museWriteMode
        refresh()
    }

    func refresh() {
        maskedToken = settings.maskedToken
        lastPush = composition.activity.lastPushAt
        exportFolderChosen = composition.export.hasDestination
        writeMode = composition.flags.document.museWriteMode
        bridge = state(of: composition.remote)
    }

    private func state(of remote: RemoteBridgeConfiguration) -> Bridge {
        switch (remote.endpoint != nil, remote.hasDeviceToken) {
        case (true, true): return .paired
        case (true, false): return .noToken
        case (false, true): return .noOrigin
        case (false, false): return .off
        }
    }

    // MARK: - Pairing

    func commitOrigin() {
        settings.save(origin: origin)
        origin = settings.origin
        composition.reconfigureRemote()
        refresh()
    }

    /// Stores a token and immediately rebuilds the bridge. Returns whether it was kept, so
    /// the sheet can stay open on a value too short to be the Worker's secret.
    @discardableResult
    func save(token: String) -> Bool {
        guard settings.save(token: token) else { return false }
        composition.reconfigureRemote()
        refresh()
        return true
    }

    func clearToken() {
        settings.clearToken()
        composition.reconfigureRemote()
        refresh()
    }

    /// Drain then push, on demand — the same call the foreground makes, so the row below it
    /// moves for the same reason it would have moved anyway.
    func syncNow() async {
        guard let engine = composition.sync, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let pending = await composition.refresher.refresh().pending
        if (try? await engine.syncNow(rollups: pending)) != nil {
            await composition.ledger.markPushed(pending)
            composition.activity.recordPush()
            composition.activity.recordDrain()
        }
        refresh()
    }

    // MARK: - Muse

    /// Flips `museWriteMode` locally and pushes the flags document, because the Worker
    /// enforces the same flag — a mode that only the phone knew about would not stop a
    /// single write.
    func apply(writeMode mode: MuseWriteMode) async {
        let document = composition.flags.setMuseWriteMode(mode)
        await composition.documentWriter().write(document, to: .flags)
        refresh()
    }

    // MARK: - Export

    func adopt(exportFolder folder: URL) {
        composition.export.adopt(folder)
        refresh()
    }
}
