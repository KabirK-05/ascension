import AscensionCore
import Foundation

/// The append-only journal (spec §9.1).
///
/// Append-only is a guarantee about history, not a file mode: a day already in the file
/// is never rewritten and never duplicated, however many times the export runs over an
/// overlapping range. The appender reads the day headers already present and emits only
/// the blocks the file has not seen.
///
/// The file is still rewritten whole and atomically rather than opened for append. An
/// `O_APPEND` write of several kilobytes is not atomic either, so a crash mid-append
/// would leave half a block — exactly the corruption this is meant to prevent — and the
/// journal is small enough that rewriting it costs nothing.
struct DailyLogAppender {
    static let fileName = "daily-log.md"
    static let title = "# Ascension — daily log"

    let renderer: DailyLogRenderer

    /// The result of folding an export's days into the journal.
    struct Append {
        /// The whole file to write, or `nil` when every day was already present.
        let contents: String?
        /// The days this export added, in order.
        let addedDates: [CalendarDate]
    }

    func append(_ rollups: [DayRollup], to existing: String?) -> Append {
        let present = Self.datesPresent(in: existing)
        let fresh = rollups.filter { !present.contains($0.date.rawValue) }
        guard !fresh.isEmpty else {
            return Append(contents: nil, addedDates: [])
        }

        let blocks = fresh.map(renderer.block)
        let contents: String
        if let existing, !existing.isEmpty {
            let base = existing.hasSuffix("\n") ? existing : existing + "\n"
            contents = base + "\n" + blocks.joined(separator: "\n")
        } else {
            contents = Self.title + "\n\n" + blocks.joined(separator: "\n")
        }
        return Append(contents: contents, addedDates: fresh.map(\.date))
    }

    /// The `YYYY-MM-DD` of every `## ` header already in the file.
    ///
    /// Matched on the header rather than on a marker comment, so a journal the user has
    /// hand-edited, or one an earlier version wrote, still parses.
    static func datesPresent(in text: String?) -> Set<String> {
        guard let text else { return [] }
        var dates: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("## ") else { continue }
            let rest = line.dropFirst(3)
            let token = rest.prefix(while: { !$0.isWhitespace })
            if CalendarDate(rawValue: String(token)) != nil {
                dates.insert(String(token))
            }
        }
        return dates
    }
}
