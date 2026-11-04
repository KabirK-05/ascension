import Foundation
import Testing

@testable import ExportKit

/// Golden-file support.
///
/// An export's whole job is the exact bytes it produces — the Worker and both MCP
/// servers read these field names — so the tests compare whole files rather than
/// sampling fields. A golden is regenerated deliberately:
///
///     ASCENSION_UPDATE_GOLDEN=1 swift test --package-path packages/ExportKit
///
/// which rewrites the files under `Tests/ExportKitTests/Golden/` so the diff of a
/// contract change is visible in review instead of hidden behind an assertion.
enum Golden {
    static var isUpdating: Bool {
        ProcessInfo.processInfo.environment["ASCENSION_UPDATE_GOLDEN"] == "1"
    }

    /// The checked-in goldens, found from this file rather than the test bundle so the
    /// update path writes back to the source tree.
    static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Golden")
    }

    static func text(_ name: String) throws -> String {
        let url = sourceDirectory.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Compares `actual` against the golden, reporting the first differing line so a
    /// failure names the line rather than printing two files.
    static func expect(_ actual: String, matches name: String,
                       sourceLocation: SourceLocation = #_sourceLocation) throws {
        if isUpdating {
            try actual.write(to: sourceDirectory.appendingPathComponent(name),
                             atomically: true, encoding: .utf8)
            return
        }
        let expected = try text(name)
        guard actual != expected else { return }
        let difference = firstDifference(actual: actual, expected: expected)
        Issue.record("\(name) differs: \(difference)", sourceLocation: sourceLocation)
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
}

/// A fresh temp directory that cleans itself up, so every test writes to the real file
/// system — the behaviour under test is file replacement, which an in-memory fake
/// would not exercise.
final class TemporaryFolder {
    let url: URL

    init(_ name: String = UUID().uuidString) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ascension-export-tests")
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func read(_ name: String) throws -> String? {
        let file = url.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }

    func write(_ contents: String, to name: String) throws {
        try contents.write(to: url.appendingPathComponent(name),
                           atomically: true, encoding: .utf8)
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
