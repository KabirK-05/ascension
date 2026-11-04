import AscensionCore
import Foundation
import SyncClient
import Testing

@testable import Ascension

/// Settings → Changes is the safety net under Muse's write authority, so the two things
/// that matter are that a row says what actually changed and that undoing one is
/// idempotent.
@Suite("change ledger")
struct ChangeLedgerTests {

    private func stamp(_ raw: String = "2026-11-05T09:00:00-05:00") -> Timestamp {
        Timestamp(rawValue: raw) ?? Timestamp(Date(), timeZone: .gmt)
    }

    private func log() -> ChangeLog {
        ChangeLog(url: FileManager.default.temporaryDirectory
            .appending(path: "changes-\(UUID().uuidString).json"))
    }

    private func change(_ id: String, summary: String = "Calories 2,200 → 2,000",
                        previous: PreviousDocument? = .goalSettings(Seed.goalSettings),
                        at raw: String = "2026-11-05T09:00:00-05:00") -> RecordedChange {
        RecordedChange(id: id, at: stamp(raw), kind: .setTargets,
                       summary: summary, previous: previous)
    }

    @Test("a target change reads as the field, the old value and the new one")
    func targetSummary() {
        var changed = Seed.goalSettings.targets
        changed.kcal = 2_000
        let text = ChangeSummary.targets(from: Seed.goalSettings.targets, to: changed)
        #expect(text.contains("Calories"))
        #expect(text.contains("→"))
        #expect(text.contains("2,000"))
    }

    @Test("several changed fields are one line, separated rather than stacked")
    func multipleFields() {
        var changed = Seed.goalSettings.targets
        changed.kcal = 2_000
        changed.proteinG = 160
        let text = ChangeSummary.targets(from: Seed.goalSettings.targets, to: changed)
        #expect(text.contains(" · "))
        #expect(text.contains("Protein"))
    }

    @Test("a write that changed nothing says so rather than inventing an arrow")
    func unchangedTargets() {
        #expect(ChangeSummary.targets(from: Seed.goalSettings.targets,
                                      to: Seed.goalSettings.targets) == "Targets unchanged")
    }

    @Test("the write mode is named as a mode, not as a raw key")
    func flagSummary() {
        #expect(ChangeSummary.flag(key: "museWriteMode", value: .string("propose"))
            == "Muse write mode propose")
        #expect(ChangeSummary.flag(key: "museWritesEnabled", value: .bool(true))
            == "Muse writes on")
    }

    @Test("rows come back newest first")
    func newestFirst() async {
        let ledger = log()
        await ledger.record(change("01", at: "2026-11-05T09:00:00-05:00"))
        await ledger.record(change("02", at: "2026-11-06T09:00:00-05:00"))
        #expect(await ledger.all().map(\.id) == ["02", "01"])
    }

    @Test("a redelivered mutation updates its row rather than adding a second")
    func redeliveryIsOneRow() async {
        let ledger = log()
        await ledger.record(change("01", summary: "first"))
        await ledger.record(change("01", summary: "second"))
        let rows = await ledger.all()
        #expect(rows.count == 1)
        #expect(rows.first?.summary == "second")
    }

    @Test("only a row with a document behind it offers an undo")
    func undoAvailability() async {
        let ledger = log()
        await ledger.record(change("01"))
        await ledger.record(change("02", previous: nil))
        let rows = await ledger.all()
        #expect(rows.first { $0.id == "01" }?.canUndo == true)
        #expect(rows.first { $0.id == "02" }?.canUndo == false)
    }

    @Test("an undone row stays in the trail and cannot be undone twice")
    func undoneRowsRemain() async {
        let ledger = log()
        await ledger.record(change("01"))
        await ledger.markUndone(id: "01", at: stamp())
        let row = await ledger.change(id: "01")
        #expect(row?.undoneAt != nil)
        #expect(row?.canUndo == false)
        #expect(await ledger.all().count == 1)
    }

    @Test("a ledger with nowhere to write keeps this launch's rows rather than trapping")
    func noFile() async {
        let ledger = ChangeLog(url: nil)
        await ledger.record(change("01"))
        #expect(await ledger.all().count == 1)
    }
}
