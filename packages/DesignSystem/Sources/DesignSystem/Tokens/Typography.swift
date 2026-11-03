import SwiftUI

/// The type ramp. Every role is built on a system text style, so Dynamic Type
/// works at every size without a call site asking for it.
///
/// Values are rounded and monospaced-digit: the hero of any card is the number
/// (§3.1), and a monospaced digit keeps it from jittering while it animates.
public enum Typography {
    /// The one number a screen exists to show.
    public static let heroValue = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    /// A number in a row or a card.
    public static let value = Font.system(.title2, design: .rounded, weight: .medium)
    /// A number inside a compact ring.
    public static let compactValue = Font.system(.title3, design: .rounded, weight: .medium)
    /// The unit that sits inline beside a value (§3.2).
    public static let unit = Font.system(.subheadline, design: .rounded)
    /// The noun above or beside a value.
    public static let label = Font.system(.subheadline)
    /// A card's own label.
    public static let cardLabel = Font.system(.footnote)
    /// A date, or anything that identifies rather than measures.
    public static let detail = Font.system(.caption)
}
