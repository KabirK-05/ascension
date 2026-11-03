import Foundation

/// One CSV field.
///
/// `null` and `text("")` are different on purpose: the contract says `null` means *not
/// measured* and never zero, so an unmeasured field is written as nothing at all while
/// a genuinely empty string is written as a quoted empty `""`. A reader can therefore
/// tell "no HRV that night" from "a note with no text".
public enum CSVValue: Hashable, Sendable {
    case null
    case text(String)
    case number(Double)
    case integer(Int)
    case flag(Bool)

    public static func optional(_ value: Double?) -> CSVValue {
        value.map(CSVValue.number) ?? .null
    }

    public static func optional(_ value: Int?) -> CSVValue {
        value.map(CSVValue.integer) ?? .null
    }

    public static func optional(_ value: String?) -> CSVValue {
        value.map(CSVValue.text) ?? .null
    }

    /// The field as it appears in the file, quoted only where RFC 4180 requires it.
    var field: String {
        switch self {
        case .null: return ""
        case .text(let value): return Self.quoted(value)
        case .number(let value): return Format.number(value)
        case .integer(let value): return String(value)
        case .flag(let value): return value ? "true" : "false"
        }
    }

    // Scalars, not `Character`s: Swift treats a CRLF pair as a single grapheme, so a
    // `Set<Character>` check would let `a\r\nb` through unquoted and split one value
    // across two CSV records.
    private static let scalarsNeedingQuotes: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]

    private static func quoted(_ value: String) -> String {
        let needsQuotes = value.isEmpty
            || value.unicodeScalars.contains(where: scalarsNeedingQuotes.contains)
            || value.hasPrefix(" ") || value.hasSuffix(" ")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// One entity's CSV: a fixed header row and its rows beneath it.
///
/// `columns` is the stable column order — the same order every export, so a diff of two
/// exports shows changed data and nothing else. Column names are the JSON field names;
/// a nested group keeps its path (`nutrition.kcal`) so the leaf name never changes
/// meaning between the two formats.
public struct CSVTable: Hashable, Sendable {
    public let name: String
    public let columns: [String]
    public let rows: [[CSVValue]]

    public init(name: String, columns: [String], rows: [[CSVValue]]) {
        self.name = name
        self.columns = columns
        self.rows = rows
    }

    public var fileName: String { "\(name).csv" }

    /// Lines are LF-terminated, including the last, which is what every spreadsheet and
    /// every unix tool reads cleanly.
    public func encoded() throws -> Data {
        for (index, row) in rows.enumerated() where row.count != columns.count {
            throw ExportError.csvRowWidthMismatch(
                table: name, row: index, expected: columns.count, found: row.count)
        }
        var text = columns.map { CSVValue.text($0).field }.joined(separator: ",")
        text.append("\n")
        for row in rows {
            text.append(row.map(\.field).joined(separator: ","))
            text.append("\n")
        }
        return Data(text.utf8)
    }
}
