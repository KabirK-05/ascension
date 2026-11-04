import AscensionCore
import Foundation
import Testing

@testable import SyncClient

@Suite("Last-write-wins merge")
struct DocumentMergeTests {
    private let earlier = Timestamp.literal("2026-11-03T18:00:00-05:00")
    private let later = Timestamp.literal("2026-11-03T23:00:00-05:00")

    @Test("fields that agree are left alone")
    func agreementIsNotAConflict() {
        let body: [String: JSONValue] = ["kcal": .number(2200)]
        let outcome = DocumentMerge.lastWriteWins(local: body, localUpdatedAt: later,
                                                  remote: body, remoteUpdatedAt: earlier)
        #expect(outcome.body == body)
        #expect(!outcome.hadConflicts)
    }

    @Test("a disagreement goes to the newer document")
    func newerDocumentWinsTheField() {
        let local: [String: JSONValue] = ["kcal": .number(2300)]
        let remote: [String: JSONValue] = ["kcal": .number(2100)]

        let localWins = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: later,
                                                    remote: remote, remoteUpdatedAt: earlier)
        #expect(localWins.body["kcal"] == .number(2300))
        #expect(localWins.takenFromLocal == ["kcal"])

        let remoteWins = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: earlier,
                                                     remote: remote, remoteUpdatedAt: later)
        #expect(remoteWins.body["kcal"] == .number(2100))
        #expect(remoteWins.takenFromRemote == ["kcal"])
    }

    @Test("a field only one side has is kept — a new field is not a disagreement")
    func oneSidedFieldsSurvive() {
        let local: [String: JSONValue] = ["kcal": .number(2300), "waistCm": .number(80)]
        let remote: [String: JSONValue] = ["kcal": .number(2300), "steps": .number(11_000)]
        let outcome = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: earlier,
                                                  remote: remote, remoteUpdatedAt: later)
        #expect(outcome.body["waistCm"] == .number(80))
        #expect(outcome.body["steps"] == .number(11_000))
        #expect(!outcome.hadConflicts)
    }

    @Test("an edit to one field does not revert the other side's edit to another")
    func independentEditsBothSurvive() {
        let local: [String: JSONValue] = ["kcal": .number(2300), "steps": .number(10_000)]
        let remote: [String: JSONValue] = ["kcal": .number(2200), "steps": .number(12_000)]
        let outcome = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: earlier,
                                                  remote: remote, remoteUpdatedAt: later)
        #expect(outcome.body["kcal"] == .number(2200))
        #expect(outcome.body["steps"] == .number(12_000))
        #expect(outcome.takenFromRemote == ["kcal", "steps"])
    }

    @Test("a tie keeps the stored copy, so two devices resolve it the same way")
    func tiesGoToTheStoredCopy() {
        let local: [String: JSONValue] = ["kcal": .number(2300)]
        let remote: [String: JSONValue] = ["kcal": .number(2100)]
        let outcome = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: later,
                                                  remote: remote, remoteUpdatedAt: later)
        #expect(outcome.body["kcal"] == .number(2100))
    }

    @Test("nested objects are compared whole, since the document stamps no inner time")
    func nestedObjectsMergeWhole() {
        let local: [String: JSONValue] = [
            "targets": .object(["kcal": .number(2300), "proteinG": .number(150)])
        ]
        let remote: [String: JSONValue] = [
            "targets": .object(["kcal": .number(2200), "proteinG": .number(160)])
        ]
        let outcome = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: later,
                                                  remote: remote, remoteUpdatedAt: earlier)
        #expect(outcome.body["targets"]
            == .object(["kcal": .number(2300), "proteinG": .number(150)]))
    }

    @Test("the merge is deterministic whichever order the keys arrive in")
    func mergeIsDeterministic() {
        let local: [String: JSONValue] = ["a": .number(1), "b": .number(2), "c": .number(3)]
        let remote: [String: JSONValue] = ["a": .number(9), "c": .number(9), "d": .number(4)]
        let first = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: earlier,
                                                remote: remote, remoteUpdatedAt: later)
        let second = DocumentMerge.lastWriteWins(local: local, localUpdatedAt: earlier,
                                                 remote: remote, remoteUpdatedAt: later)
        #expect(first == second)
        #expect(first.takenFromRemote == ["a", "c"])
    }
}
