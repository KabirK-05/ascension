import SwiftUI
import UIKit

/// Semantic colour. Call sites never name a raw value — they name a meaning.
///
/// Surfaces and text are the system's own, so both appearances are correct by
/// construction (`docs/DESIGN_RULES.md` §4.3). Only the accent and the
/// consistency ramp are ours, and colour carries status, never theme (§2.4).
public enum Palette {

    // MARK: Surfaces

    /// The page. Grouped, so light mode is grey behind white cards and dark
    /// mode is black behind near-black ones — the system's own inset-grouped look.
    public static let background = Color(uiColor: .systemGroupedBackground)
    public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    public static let surfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)
    public static let separator = Color(uiColor: .separator)

    // MARK: Text

    public static let primaryText = Color(uiColor: .label)
    public static let secondaryText = Color(uiColor: .secondaryLabel)
    public static let tertiaryText = Color(uiColor: .tertiaryLabel)

    // MARK: Status

    /// The one accent. A screen shows at most one (§2.4).
    public static let accent = dynamic(dark: 0x3C_D4_8C, light: 0x0C_9B_5C)
    /// Reserved for a value that has run past its target.
    public static let caution = Color(uiColor: .systemOrange)
    /// Reserved for a value that needs action today.
    public static let critical = Color(uiColor: .systemRed)
    /// The unfilled remainder of a ring or a progress track.
    public static let track = Color(uiColor: .quaternarySystemFill)

    // MARK: Consistency ramp (§6.5)

    /// A single hue at five steps, including empty. Step 0 is a near-background
    /// fill — never a border.
    public static func consistency(_ intensity: Int) -> Color {
        switch min(max(intensity, 0), 4) {
        case 1: return dynamic(dark: 0x16_43_2F, light: 0xC9_EE_DB)
        case 2: return dynamic(dark: 0x1E_6B_47, light: 0x8C_D9_B4)
        case 3: return dynamic(dark: 0x27_A1_69, light: 0x3F_AF_7C)
        case 4: return accent
        default: return Color(uiColor: .tertiarySystemFill)
        }
    }
}

private func dynamic(dark: UInt32, light: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? solid(dark) : solid(light)
    })
}

private func solid(_ hex: UInt32) -> UIColor {
    UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}
