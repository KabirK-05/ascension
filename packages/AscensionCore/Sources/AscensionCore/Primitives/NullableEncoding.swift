import Foundation

extension KeyedEncodingContainer {
    /// Encodes `value`, writing an explicit `null` when it is `nil`.
    ///
    /// The contract spells out `null` for every unmeasured field, and `null` there means
    /// *not measured* rather than *absent*. A reader that validates a field as nullable
    /// but not optional would reject an omitted key, so the key is always written.
    public mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
