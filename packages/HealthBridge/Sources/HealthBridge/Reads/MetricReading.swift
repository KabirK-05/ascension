import Foundation

/// Why a reading has no value.
///
/// `noDataOrNoPermission` is one case on purpose. HealthKit answers a denied read with an
/// empty result, identical to a day with nothing recorded, so this module cannot tell the
/// two apart and does not pretend to. Callers that want to say something to the user say
/// "no data" — never "permission denied" — unless a write scope proves otherwise.
public enum ReadingGap: Hashable, Sendable {
    case noDataOrNoPermission
    case healthDataUnavailable
    case queryFailed(String)
}

/// A measurement, or an honest account of why there isn't one.
public enum MetricReading<Value: Hashable & Sendable>: Hashable, Sendable {
    case measured(Value)
    case missing(ReadingGap)

    public var value: Value? {
        switch self {
        case .measured(let value): return value
        case .missing: return nil
        }
    }

    public var isMeasured: Bool { value != nil }

    public func map<Other: Hashable & Sendable>(_ transform: (Value) -> Other) -> MetricReading<Other> {
        switch self {
        case .measured(let value): return .measured(transform(value))
        case .missing(let gap): return .missing(gap)
        }
    }

    /// Wraps an optional, treating `nil` as the uncertain case rather than as a zero.
    public static func from(_ value: Value?) -> MetricReading<Value> {
        guard let value else { return .missing(.noDataOrNoPermission) }
        return .measured(value)
    }
}
