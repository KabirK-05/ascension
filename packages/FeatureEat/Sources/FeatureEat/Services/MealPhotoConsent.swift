import Foundation

/// Whether the user has agreed that a photograph of their food may leave the device.
///
/// Spec §4 is local-first and §8 allows no analytics and no third parties; the photo
/// path is the one place in this app that sends the user's own content somewhere else.
/// That is a decision worth asking for out loud, at the point of use, and worth being
/// able to take back — so it is a stored answer rather than an assumption, and it gates
/// `AnthropicMealVision` itself rather than only the screen that calls it.
public protocol MealPhotoConsenting: Sendable {
    var isGranted: Bool { get }
    func grant()
    func revoke()
}

/// The answer, in `UserDefaults`. Not the Keychain: it is a preference, not a secret,
/// and the user must be able to find and change it.
///
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` and is
/// documented thread-safe; nothing is cached here, so every read asks it afresh.
public final class DefaultsMealPhotoConsent: MealPhotoConsenting, @unchecked Sendable {
    static let key = "com.kabirkumar.ascension.eat.photoConsent"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isGranted: Bool { defaults.bool(forKey: Self.key) }

    public func grant() { defaults.set(true, forKey: Self.key) }

    public func revoke() { defaults.set(false, forKey: Self.key) }
}

/// Consent with nothing behind it, for previews and tests.
public final class EphemeralMealPhotoConsent: MealPhotoConsenting, @unchecked Sendable {
    private let lock = NSLock()
    private var granted: Bool

    public init(granted: Bool = false) {
        self.granted = granted
    }

    public var isGranted: Bool { lock.withLock { granted } }

    public func grant() { lock.withLock { granted = true } }

    public func revoke() { lock.withLock { granted = false } }
}
