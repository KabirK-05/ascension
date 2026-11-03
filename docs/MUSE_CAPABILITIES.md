# What Muse can do

The contract for the MCP tool surface (ASC-6 read, ASC-13 write). Three tiers, defined
by **where the data lives**, which is the only thing that actually constrains Muse.

---

## Tier 1 — Muse owns outright (cloud-side, instant)

These live as JSON documents in D1. Muse is a first-class editor; changes are live the
moment the app next reads them, and the app never has to be open.

| Capability | Tool | Notes |
|---|---|---|
| Calorie + macro targets | `set_targets` | kcal, protein, fat floor, carb remainder. Guardrails: fat never below 60 g (spec §2). |
| The whole training program | `update_program` | Which weekday is which session, exercise list per session, sets/reps, finisher flags, progression increment. Can restructure Upper/Lower → full-body and back; the model holds both shapes (spec §3). |
| Swap today's session | `update_program` | "Legs are sore, make today Upper B" — the §F5 constraint (never a muscle group trained <48 h ago) is enforced server-side, so Muse cannot write an invalid week. |
| Deload | `update_program` | Flip a week to ~60% load / half volume. |
| Staple foods + macros | `set_staples` | The one-tap quick-add list is config, not code. |
| Accept a calorie suggestion | `accept_suggestion` | The weekly auto-adjust (§F6) becomes a thing Muse can action on your behalf. |
| Feature flags | `set_flag` | Per your standing rule, phase behaviour is a flag flip. |

## Tier 2 — Muse requests, the phone performs (queued, usually seconds)

These require a device-only API. Muse appends a mutation; a silent APNs push wakes the
phone, which applies it and writes to Apple Health — typically within seconds, falling
back to next foreground if push doesn't land. **These tools return
`pending_device_apply`**, so Muse never tells you a thing hit Apple Health when it
hasn't yet.

| Capability | Tool | Why it needs the device |
|---|---|---|
| Log a meal | `log_meal` | Writes dietary energy/protein/carb/fat to HealthKit. Device-only API. |
| Log water | `log_water` | HealthKit write. |
| Log a top set | `log_top_set` | App-owned, but feeds the on-device progression view. |
| Log the morning check-in | `log_checkin` | Soreness + energy. |
| Send a session to the Watch | `schedule_workout` | WorkoutKit schedules from the device. Muse can only ask. |
| Force an export | `trigger_export` | Writes to your iCloud Drive folder. |

## Tier 3 — Muse reads

`get_today`, `get_workouts`, `get_nutrition`, `get_weight_trend`, `get_readiness`,
`get_checkins`, `get_exercise_history`, `get_consistency_grid`.

Scoped to **daily rollups** by your choice: totals, trends, readiness scores and
reasons, top sets, adherence, the grid's four daily wins. Enough to answer "how is my
training going this month?" accurately — which is the spec's acceptance test (§9.3).

---

## What Muse genuinely cannot do

Worth knowing up front, so you don't design around a capability that isn't there:

1. **Record a workout.** The Apple Watch Workout app does that. Non-negotiable
   (spec principle 1). Muse plans and interprets; it never records.
2. **Read HealthKit live.** HealthKit is not reachable from outside the phone — that
   is the entire reason this bridge exists. Muse sees what the phone has pushed, so
   data is as fresh as the last sync, not real-time.
3. **Write to Apple Health directly.** Only Tier 2, via the phone.
4. **See per-meal rows, raw HR series, or sleep stages.** Your rollups-only scope.
   The `rawDetailSyncEnabled` flag is the escape hatch if you later want it.
5. **Delete anything.** No delete tools in v1.

---

## Safety: full authority, with an undo

You asked that Muse "handle and use this app exactly like I can", so the default is
`museWriteMode: apply` — writes take effect immediately, no confirmation.

Two things make that safe rather than reckless:

- **The `mutations` table is append-only**, so every change Muse ever makes is an
  audit log with an actor and a timestamp.
- **Settings → Changes** lists every Muse write in plain language ("Calorie target
  2,200 → 2,000 · Nov 5") with **one-tap undo** on targets and program edits.

If that ever feels too loose, the `museWriteMode` flag flips to `propose`: writes
become pending suggestions that surface on Today for one-tap accept, which is closer
to the spec's "never change targets silently" instinct (§F6). Flag flip, no release.
