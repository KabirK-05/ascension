# SyncClient (ASC-12)

The device half of the cloud bridge. `docs/TECH_STACK.md` §2.3 defines two streams that
flow in opposite directions, and this package is the phone's end of both.

```
Stream A  observed   phone → POST /v1/ingest → rollups          one-way, upsert on date
Stream B  intent     documents + mutations  ↔ phone             two-way, If-Match + ULID log
```

Depends on `AscensionCore` and nothing else. `URLSession`, the Keychain, the clock,
HealthKit and the local store are all behind protocols, so the whole package builds and
tests on macOS — which is where CI runs it.

## Wiring it up

```swift
let engine = SyncEngine.live(
    origin: SyncEndpoint(origin: "https://<worker>.workers.dev"),
    tokens: KeychainDeviceTokenStore(),
    local: MyLocalStateApplier(modelContext: context),   // your LocalStateApplier
    health: HealthBridgeWriteBack(writer: healthWriter),  // your HealthWriteBack
    state: try FileSyncStateStore.applicationSupport(),
    clock: SystemClock(timeZoneIdentifier: goalSettings.timezone))

try await engine.syncNow(rollups: rollupsThatChanged)    // drain, then push
```

`HealthWriteBack` is declared here rather than imported: adapt it to `HealthBridge`'s
`HealthWriter` in the app shell, and **pass the mutation id straight through as the entry
id** — that is what makes a repeated `log_meal` a replacement in HealthKit rather than a
second meal.

## Assembling a rollup

```swift
let measured = snapshot.applied(to: existing, timeZone: tz)   // HealthBridge's half
let rollup = RollupAssembler.assemble(measured: measured, device: deviceDay,
                                      goals: goalSettings, clock: clock)
```

`DeviceDay` carries the half HealthKit cannot know: logged meals, the planned session,
top sets, the check-in, the readiness rollup from `AscensionEngines`, and the three
rolling numbers (`weightAvg7Kg`, `rateKgPerWeek`, `consistencySd7Minutes`) the engines
own. `wins` is **not** computed here — it comes from `AscensionCore.WinsCalculator`,
because the contract says the device computes it once and the Worker stores what it was
sent.

## Background and push

| Identifier | Task | Work |
|---|---|---|
| `…nightly-export` | `BGProcessingTask` | `ExportKit`'s nightly export **and** the rollup push |
| `…rollup-sync` | `BGAppRefreshTask` | the mutation drain |

Those are the only two identifiers `Project.swift` permits. The nightly one is shared with
`ExportKit`, and `BGTaskScheduler` allows one handler per identifier, so the app shell
registers it once and calls both. `BackgroundSyncCoordinator.registerMutationDrain()`
owns the refresh task outright.

A silent APNs push (`SilentPushHandler`) makes a drain happen in seconds instead of at the
next refresh. It is an accelerator only: foreground sync and background refresh do
everything it does, so nothing is correct *because* a push arrived.

**Registering the nightly handler will fight Swift 6.** `BGTask` is not `Sendable` and the
work is async, so the task has to outlive the launch handler — and the handler is
task-isolated, so hopping to the main actor does not rescue it. There is no spelling
complete concurrency checking accepts; `registerMutationDrain` marks the one crossing
`nonisolated(unsafe)` with the reasoning written out, and the nightly handler in the app
shell will need the same. This package builds in Swift 6 language mode precisely so that
shows up here rather than only in the `app` job.

## Four things that will bite you

1. **A document `PUT` body carries no `version`, `updatedAt` or `updatedBy`.** Those are
   columns on the Worker's `documents` table. `AscensionCore`'s document types carry them
   inline, so `RemoteDocument.body(of:)` strips them — along with the `schemaVersion` every
   response adds. A body that echoes any of them fails the Worker's `strictObject`.
2. **A failed mutation blocks the drain.** It is not skipped: applying Muse's later writes
   over a failed earlier one would leave her intent half-applied and out of order. The
   `DrainReport` names the blocker and how many times it has failed.
3. **`SyncState` must be durable, not just persisted.** A mutation is recorded as applied
   *before* its ack is attempted, because the ack is the part that fails. Lose that file and
   a queued meal can be applied twice — HealthKit's sync identifier is then the only thing
   standing between you and a double-logged lunch.
4. **`null` is not zero.** A macro no meal carried stays `nil` and is encoded as an
   explicit `null`. `edge/src/contract.ts` declares these `.nullable()` without
   `.optional()`, so an omitted key is a contract violation, not a shrug.

## Verifying the contract

```
ASCENSION_UPDATE_GOLDEN=1 swift test --package-path packages/SyncClient
python3 packages/SyncClient/Scripts/verify-contract-field-names.py .
```

The goldens under `Tests/SyncClientTests/Golden/` are the exact bodies this client sends.
The script diffs them against the zod schemas in `edge/src/contract.ts`, the closed sets in
both, and the mutation-kind table in `docs/EXPORT_SCHEMA.md` §3. Run it after any contract
change — nothing in either compiler can catch a rename across the two languages.
