import Foundation
import Testing

@testable import SyncClient

/// Golden-file support, following `ExportKit`'s.
///
/// The goldens here are the exact request bodies this client puts on the wire, and
/// `Scripts/verify-contract-field-names.py` diffs them against `edge/src/contract.ts`. A
/// field rename on either side is otherwise a silent break — the Worker would answer
/// `contract_violation` the first time a real device syncs.
///
/// Regenerated deliberately:
///
///     ASCENSION_UPDATE_GOLDEN=1 swift test --package-path packages/SyncClient
enum Golden {
    static var isUpdating: Bool {
        ProcessInfo.processInfo.environment["ASCENSION_UPDATE_GOLDEN"] == "1"
    }

    /// Found from this file rather than from a test bundle, so the update path writes back
    /// into the source tree where it can be reviewed.
    static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Golden")
    }

    static func expect(_ actual: String, matches name: String,
                       sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = sourceDirectory.appending(path: name)
        if isUpdating {
            try FileManager.default.createDirectory(at: sourceDirectory,
                                                    withIntermediateDirectories: true)
            try (actual + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        guard actual + "\n" != expected else { return }
        Issue.record("\(name) differs: \(firstDifference(actual: actual, expected: expected))",
                     sourceLocation: sourceLocation)
    }

    private static func firstDifference(actual: String, expected: String) -> String {
        let left = actual.split(separator: "\n", omittingEmptySubsequences: false)
        let right = expected.split(separator: "\n", omittingEmptySubsequences: false)
        for index in 0..<max(left.count, right.count) {
            let actualLine = index < left.count ? String(left[index]) : "<end of file>"
            let expectedLine = index < right.count ? String(right[index]) : "<end of file>"
            if actualLine != expectedLine {
                return "line \(index + 1)\n  actual:   \(actualLine)\n"
                    + "  expected: \(expectedLine)"
            }
        }
        return "lengths differ (\(left.count) vs \(right.count) lines)"
    }

    static func pretty(_ value: some Encodable & Sendable) throws -> String {
        let data = try SyncCoding.prettyEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TestFailure(description: "encoded JSON was not UTF-8")
        }
        return text
    }
}
