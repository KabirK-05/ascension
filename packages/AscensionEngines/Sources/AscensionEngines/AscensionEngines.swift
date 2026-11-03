/// Readiness (spec §F5), trends (spec §F6) and the calorie rules.
///
/// Spec §8 calls these the product: "pure Swift functions over value types [that] must
/// ship with unit tests". Four properties hold across the whole module, and a change that
/// breaks one of them is a bug even if it compiles:
///
/// - **Pure.** Every entry point is a function of its arguments. No singleton, no cache,
///   no `Date()`, no `Calendar.current` — the clock arrives as ``EngineClock`` and day
///   arithmetic runs on integers (`CalendarMath.swift`), so a verdict is reproducible
///   from an exported day on any machine, forever.
/// - **`null` is not zero.** `nil` means *not measured* (`docs/EXPORT_SCHEMA.md`). An
///   absent signal leaves the score's weighted mean rather than scoring zero, and narrows
///   ``ReadinessAssessment/confidence`` instead.
/// - **Legality is not negotiable.** ``SessionLegality`` alone decides what may be
///   trained; the score only decides how hard. No score can unlock a muscle region inside
///   its 48 h window or marked sore.
/// - **Suggest-only.** Nothing here writes. The calorie rule returns a
///   ``CalorieSuggestion``; it never emits a `Mutation` and never edits a target.
///
/// Readiness output is training guidance, never medical advice or diagnosis (spec §12).
///
/// Depends on `AscensionCore` and nothing else — no SwiftUI, no HealthKit, no I/O.
public enum AscensionEnginesModule {
    /// Schema contract version this module is written against.
    /// See `docs/EXPORT_SCHEMA.md`.
    public static let schemaVersion = 1
}
