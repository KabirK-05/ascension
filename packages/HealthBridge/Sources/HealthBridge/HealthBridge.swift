/// HealthKit read/write, mirrors and background delivery (spec §6).
///
/// The module is arranged around one constraint: HealthKit exists on iOS and nowhere
/// else, so every framework call sits behind the `HealthStore` protocol and
/// `HKHealthStoreAdapter` is the only file that imports HealthKit. Mirrors, zones,
/// aggregation, idempotency and the write surface are plain value logic over value types,
/// and are tested against a fake store.
///
/// Apple records; this app manages (spec §1). Nothing here starts, writes or finishes a
/// workout — there is no `HKWorkoutSession` in this package and there must never be one.
public enum HealthBridgeModule {
    /// Schema contract version this module is written against.
    /// See `docs/EXPORT_SCHEMA.md`.
    public static let schemaVersion = 1
}
