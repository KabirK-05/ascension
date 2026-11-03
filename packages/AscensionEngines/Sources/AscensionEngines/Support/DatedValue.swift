import AscensionCore
import Foundation

/// One measurement on one day — the shape every trend series takes.
///
/// A series holds only the days that carry a measurement. Nothing is zero-filled: `null`
/// means *not measured* in the contract (`docs/EXPORT_SCHEMA.md`), and a zero-filled gap
/// would read as a real reading of zero in a chart and in an average.
public struct DatedValue: Hashable, Sendable {
    public let date: CalendarDate
    public let value: Double

    public init(date: CalendarDate, value: Double) {
        self.date = date
        self.value = value
    }
}

extension Array where Element == DatedValue {
    /// The series, earliest first.
    var chronological: [DatedValue] { sorted { $0.date < $1.date } }

    /// The most recent value at or before `date`.
    func latest(onOrBefore date: CalendarDate) -> DatedValue? {
        chronological.last { $0.date <= date }
    }

}
