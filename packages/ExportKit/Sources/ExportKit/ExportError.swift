import Foundation

/// Everything an export can fail on, named so a failure says what went wrong rather
/// than surfacing a bare `NSError` from the file system.
public enum ExportError: Error, Equatable, CustomStringConvertible {
    /// No folder has been chosen yet, so there is nowhere to write.
    case noDestinationChosen
    /// The stored bookmark no longer resolves — the folder was deleted, renamed beyond
    /// recovery, or iCloud revoked access.
    case destinationUnresolvable(String)
    /// The resolved folder refused a security-scoped access request.
    case destinationAccessDenied(String)
    /// The resolved path is not a directory.
    case destinationNotADirectory(String)
    /// A temp file was written but could not replace its destination; the previous file
    /// is untouched.
    case atomicReplaceFailed(file: String, reason: String)
    /// A table was built with a row that does not match its header.
    case csvRowWidthMismatch(table: String, row: Int, expected: Int, found: Int)
    /// `summary-latest.md` came out longer than the contract allows.
    case summaryTooLong(lines: Int, limit: Int)

    public var description: String {
        switch self {
        case .noDestinationChosen:
            return "No export folder has been chosen."
        case .destinationUnresolvable(let reason):
            return "The export folder could not be resolved: \(reason)"
        case .destinationAccessDenied(let path):
            return "Access to the export folder was denied: \(path)"
        case .destinationNotADirectory(let path):
            return "The export destination is not a folder: \(path)"
        case .atomicReplaceFailed(let file, let reason):
            return "Could not replace \(file); the previous file is intact: \(reason)"
        case .csvRowWidthMismatch(let table, let row, let expected, let found):
            return "\(table).csv row \(row) has \(found) fields, expected \(expected)."
        case .summaryTooLong(let lines, let limit):
            return "summary-latest.md is \(lines) lines; the limit is \(limit)."
        }
    }
}
