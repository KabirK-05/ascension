import AscensionCore
import Foundation

/// The few words the surfaces outside the app put next to a number.
///
/// `FeatureToday` has its own copy of the verdict wording, and this is deliberately a
/// second one rather than a dependency: a widget extension that imported a feature would
/// drag SwiftUI screens, fixtures and a check-in store into a process that draws one
/// number. Two lines of text, kept in the one place every surface reads.
public enum SurfaceText {
    public static func verdict(_ verdict: ReadinessVerdict) -> String {
        switch verdict {
        case .trainAsPlanned: return "Train as planned"
        case .capIntensity: return "Cap intensity"
        case .swapSession: return "Swap session"
        case .activeRecovery: return "Active recovery"
        }
    }

    /// Grams, as a whole number — §3.4: never a precision the data does not have.
    public static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }
}
