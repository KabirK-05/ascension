# Ascension — Data Contract

`schemaVersion: 1`

**This file is the contract between the app, the Cloudflare Worker, and both MCP
servers.** It is what lets the edge work proceed in parallel with the app work. Any
field change bumps `schemaVersion` and updates this file in the same PR.

Units are fixed everywhere: **kg, kcal, grams, millilitres, minutes, bpm, ms**.
All timestamps are **ISO 8601 with offset**. All dates are `YYYY-MM-DD` in the user's
timezone (`America/Toronto`). `null` means *not measured*; it never means zero.

---

## 1. `DayRollup` — the core object

One per day. The unit of sync (`POST /v1/ingest`), the unit most MCP reads return, and
the source of the Today screen's consistency grid. Upserted on `date`, so re-sending a
day is always safe.

```json
{
  "date": "2026-11-03",
  "timezone": "America/Toronto",
  "updatedAt": "2026-11-03T23:05:00-05:00",

  "nutrition": { "kcal": 2180, "proteinG": 148, "fatG": 64, "carbsG": 248, "waterMl": 2400 },
  "activity":  { "steps": 10240, "activeEnergyKcal": 612, "exerciseMinutes": 54, "standHours": 10 },
  "sleep":     { "asleepMinutes": 462, "inBedMinutes": 495, "consistencySd7Minutes": 34 },
  "vitals":    { "restingHrBpm": 58, "hrvSdnnMs": 41, "vo2Max": 44.2, "respiratoryRate": 14.1, "spo2Pct": 97 },
  "body":      { "weightKg": 73.6, "weightAvg7Kg": 73.9, "rateKgPerWeek": -0.4, "bodyFatPct": null, "waistCm": null },

  "training": {
    "sessionPlanned": "upperA",
    "sessionDone": true,
    "loadAu": 6120,
    "workouts": [{
      "healthKitId": "A1B2C3D4-0000-0000-0000-000000000001",
      "type": "traditionalStrengthTraining",
      "startedAt": "2026-11-03T19:04:00-05:00",
      "endedAt":   "2026-11-03T19:55:00-05:00",
      "durationMinutes": 51,
      "activeEnergyKcal": 368,
      "hrAvgBpm": 120,
      "hrMaxBpm": 150,
      "timeInZonesMinutes": { "z1": 4, "z2": 22, "z3": 18, "z4": 6, "z5": 1 },
      "source": "Apple Workout"
    }],
    "topSets": [
      { "exerciseId": "Goblet_Squat", "weightKg": 24.0, "reps": 12 },
      { "exerciseId": "DB_Bench_Press", "weightKg": 20.0, "reps": 11 }
    ]
  },

  "checkIn": {
    "energy": 4,
    "soreness": { "chest": "none", "back": "mild", "shoulders": "none",
                  "arms": "none", "quads": "sore", "hamstrings": "mild", "glutes": "none", "core": "none" }
  },

  "readiness": {
    "score": 82,
    "verdict": "trainAsPlanned",
    "reasons": ["slept 7h42", "HRV near baseline"]
  },

  "wins": { "session": true, "protein": true, "steps": true, "sleep": true, "total": 4 }
}
```

### Enums (closed sets — reject anything else)

| Field | Values |
|---|---|
| `training.sessionPlanned` | `upperA` `upperB` `lowerA` `lowerB` `fullBody` `zone2` `rest` `null` |
| `readiness.verdict` | `trainAsPlanned` `capIntensity` `swapSession` `activeRecovery` |
| `checkIn.soreness.*` | `none` `mild` `sore` |
| `checkIn.energy` | integer `1`–`5` |
| `wins.*` | boolean; `total` is `0`–`4` |

### `wins` — the consistency grid, defined once

`wins` is computed **on device** and stored, never recomputed by the Worker, so the
grid can never disagree with itself across clients.

| Win | True when |
|---|---|
| `session` | `sessionDone`, **or** `sessionPlanned == "rest"` and no workout landed |
| `protein` | `nutrition.proteinG >= goalSettings.targets.proteinMinG` (140) |
| `steps` | `activity.steps >= goalSettings.targets.steps` (10,000) |
| `sleep` | `sleep.asleepMinutes >= goalSettings.targets.sleepMinutes` (450) |

A win against a `null` measurement is `false`, never `true`. `total` is the count.

### `loadAu`

Training load in arbitrary units: `Σ durationMinutes × intensityFactor`, where
`intensityFactor = hrAvgBpm / restingHrBpm`. Consumed by the acute:chronic ratio in
F6. Defined here so the app and the Worker never compute it differently.

---

## 2. Documents — the mutable state Muse may write

Each is a single JSON document in D1 with an integer `version` that increments on
every write. Concurrency is `If-Match: <version>`; a mismatch returns `409` with the
current document, and the loser merges last-write-wins per field by timestamp.

### 2.1 `goalSettings`

```json
{
  "version": 7,
  "updatedAt": "2026-11-03T18:00:00-05:00",
  "updatedBy": "muse",
  "targets": { "kcal": 2200, "proteinG": 150, "proteinMinG": 140,
               "fatMinG": 60, "fatMaxG": 70, "steps": 10000, "sleepMinutes": 450 },
  "body": { "goalWeightKg": 68.0, "heightCm": 170 },
  "programStartDate": "2026-11-03",
  "deloadEveryWeeks": 5,
  "timezone": "America/Toronto",
  "dietaryRules": {
    "excludedMeats": ["pork", "beef"],
    "allowedDairy": ["milk_bournvita"],
    "noLiquidCalories": true
  }
}
```

**Server-enforced invariants** (reject the write, don't clamp silently):
`targets.fatMinG >= 60` · `targets.kcal` in `1400..4000` ·
`targets.proteinMinG <= targets.proteinG` · `dietaryRules.excludedMeats` always
contains `pork` and `beef` (spec §2 is a hard constraint, not a preference).

### 2.2 `program`

```json
{
  "version": 3,
  "updatedAt": "2026-11-03T18:00:00-05:00",
  "updatedBy": "device",
  "name": "Upper/Lower 4-day",
  "days": [
    { "weekday": 1, "kind": "upperA" }, { "weekday": 2, "kind": "lowerA" },
    { "weekday": 3, "kind": "rest"   }, { "weekday": 4, "kind": "upperB" },
    { "weekday": 5, "kind": "lowerB" }, { "weekday": 6, "kind": "rest"   },
    { "weekday": 7, "kind": "rest"   }
  ],
  "sessions": {
    "upperA": {
      "name": "Upper A",
      "exercises": [
        { "order": 1, "exerciseId": "DB_Bench_Press",  "sets": 3, "repsLow": 10, "repsHigh": 12, "finisher": false },
        { "order": 2, "exerciseId": "Lat_Pulldown",    "sets": 3, "repsLow": 10, "repsHigh": 12, "finisher": false },
        { "order": 3, "exerciseId": "Overhead_DB_Press","sets": 3, "repsLow": 10, "repsHigh": 12, "finisher": false },
        { "order": 4, "exerciseId": "Seated_Cable_Row", "sets": 3, "repsLow": 10, "repsHigh": 12, "finisher": false }
      ]
    }
  },
  "progression": { "rule": "rir2", "incrementKg": 2.5 },
  "finisher": { "kind": "inclineWalk", "minutes": 15, "inclinePct": 9, "daysPerWeek": 2 },
  "deload": { "active": false, "loadFactor": 0.6, "volumeFactor": 0.5 }
}
```

`weekday` is ISO-8601: Monday = 1. `exerciseId` references free-exercise-db ids.
`days` must hold exactly 7 entries. The model intentionally also expresses the
historical Mon/Thu full-body + Wed/Sat Zone 2 shape (spec §3).

**Server-enforced invariant (spec §F5):** no two non-rest days training the same
muscle group may sit less than 48 h apart. A write that violates it is rejected with
the offending pair named — so Muse cannot author an invalid week.

### 2.3 `flags`

```json
{
  "version": 2,
  "remoteBridgeEnabled": true,
  "museWritesEnabled": true,
  "museWriteMode": "apply",
  "rawDetailSyncEnabled": false,
  "foundationModelsEnabled": true
}
```

`museWriteMode` is `apply` | `propose`. Read at runtime by both the app and the
Worker, so launch-phase behaviour is a flag flip, never a release.

---

## 3. Mutations — the append-only write log

```json
{
  "id": "01JC8X9Y2K3M4N5P6Q7R8S9T0V",
  "createdAt": "2026-11-03T18:00:00-05:00",
  "actor": "muse",
  "kind": "log_meal",
  "payload": { "...": "kind-specific" },
  "appliedAt": null,
  "appliedResult": null
}
```

`id` is a ULID, so ordering is lexicographic. `actor` is `muse` | `device` | `system`.
`appliedAt` is set by the **device** after it applies a Tier-2 mutation; Tier-1
mutations are applied by the Worker and marked immediately.

### Kinds

| Kind | Tier | Payload |
|---|---|---|
| `set_targets` | 1 | partial `goalSettings.targets` |
| `update_program` | 1 | full `program` document body |
| `set_staples` | 1 | `{ staples: FoodItem[] }` |
| `set_flag` | 1 | `{ key, value }` |
| `accept_suggestion` | 1 | `{ suggestionId }` |
| `log_meal` | 2 | `{ date, meal, items: [{ foodItemId?, name, grams, kcal, proteinG, fatG, carbsG }] }` |
| `log_water` | 2 | `{ date, ml }` |
| `log_top_set` | 2 | `{ date, exerciseId, weightKg, reps }` |
| `log_checkin` | 2 | `{ date, energy, soreness }` |
| `schedule_workout` | 2 | `{ date, sessionKind }` |
| `trigger_export` | 2 | `{}` |

`meal` is `breakfast` | `lunch` | `dinner` | `snack`.

**Tier-2 tools must return `pending_device_apply`.** An assistant may never report a
HealthKit write as complete before the device has applied it.

---

## 4. File exports (spec §9.1)

Unchanged from the spec, generated by `ExportKit`, written atomically (temp file then
rename) into the user's chosen iCloud Drive folder:

- **`export.json`** — `{ schemaVersion, exportedAt, recordCounts, rollups[], documents{}, meals[], topSets[], checkIns[], readiness[], workouts[], sleep[], weight[] }`
- **CSV per entity** — one file each, header row, same field names as the JSON
- **`daily-log.md`** — append-only, one block per day, exactly the spec §9.1 shape
- **`summary-latest.md`** — rolling 28 days, overwritten, **under 150 lines**

`export.json` is the superset; `DayRollup` is the subset that leaves the device under
the rollups-only scope. `rawDetailSyncEnabled` is what would widen cloud sync to the
full set.
