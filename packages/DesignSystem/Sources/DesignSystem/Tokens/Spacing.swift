import CoreGraphics

/// The spacing scale. Four-point steps, named by relationship rather than size.
public enum Spacing {
    /// Between a value and its unit.
    public static let hairline: CGFloat = 2
    /// Inside a control.
    public static let tight: CGFloat = 4
    /// Between two parts of the same thing.
    public static let snug: CGFloat = 8
    /// Between rows in a list.
    public static let regular: CGFloat = 12
    /// Between a card's edge and its content.
    public static let roomy: CGFloat = 16
    /// Between cards.
    public static let section: CGFloat = 24

    /// Padding inside every `StatCard`.
    public static let cardPadding: CGFloat = 16
    /// The margin from the screen edge.
    public static let screenMargin: CGFloat = 16
    /// The gap between two consistency cells.
    public static let gridCellGap: CGFloat = 3
}
