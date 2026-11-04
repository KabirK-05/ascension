import CoreGraphics

/// Corner radii. Continuous curvature everywhere, as the system uses.
public enum Radius {
    public static let card: CGFloat = 16
    public static let control: CGFloat = 10
    /// A consistency cell. Small enough to still read as a square.
    public static let cell: CGFloat = 2.5
}
