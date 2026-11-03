/// Cloudflare push/pull and mutation application (`docs/TECH_STACK.md` §2.3).
///
/// Two streams, in opposite directions:
///
/// - **Stream A — observed.** The phone assembles one `DayRollup` per day and pushes it
///   to `POST /v1/ingest`, which upserts on `date`. One-way, and safe to repeat.
/// - **Stream B — intent.** D1 holds the three mutable documents and an append-only
///   mutation log. The phone drains the log, applies each mutation locally — writing
///   through to Apple Health for the `log_*` kinds — and acks what it applied.
///
/// Everything here is testable on macOS: `URLSession` sits behind ``HTTPTransport``, the
/// Keychain behind ``DeviceTokenStore``, and the clock behind ``SyncClock``. The package
/// depends on `AscensionCore` and nothing else, so applying a Tier-2 mutation goes through
/// ``HealthWriteBack``, which the app shell satisfies with `HealthBridge`.
public enum SyncClientModule {
    /// Schema contract version this module is written against.
    /// See `docs/EXPORT_SCHEMA.md`.
    public static let schemaVersion = 1
}
