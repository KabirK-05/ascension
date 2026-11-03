# Recomp — Personal Health Manager (working title)

**Product spec for Claude Code.** Build this project from this document. Where this
spec gives an instruction ("use Mobbin MCP before building this screen"), treat it
as a build requirement, not a suggestion.

One-liner: **Apple records the data; this app manages it.** A personal, single-user
iOS app that sits on top of Apple Health and the Apple Watch Workout app —
planning training, logging food, scoring readiness, tracking trends toward a
fat-loss + muscle-building goal — and exports everything in formats an AI
assistant (Muse) can read.

---

## 1. Principles (do not violate)

1. **No custom workout recording.** The user records workouts in Apple's Workout
   app on Apple Watch. This app never builds a recorder, GPS tracker, or set-by-set
   live logger. It *plans* workouts (WorkoutKit → Watch), *reads* results
   (HealthKit), and *interprets* them.
2. **HealthKit is the source of truth** for workouts, heart rate, HRV, resting HR,
   VO2 max, sleep, steps, energy, and body weight. The app mirrors what it needs
   for trends and export; it does not fork the truth.
3. **Data ownership is a feature, not an afterthought.** Every piece of data the
   app owns or derives must be exportable in open formats and readable by Muse
   via files or MCP (see §9). If a feature can't be exported, don't build it.
4. **Local-first, no backend (v1).** SwiftData on device, optional private iCloud
   sync. No accounts, no servers, no analytics, no third-party tracking.
5. **Single user.** The app is hardcoded around one person's program, targets,
   and staple foods (all stored as editable data/config, not UI assumptions).
   Installed via Xcode on the user's own phone. Not an App Store product.
6. **Small slices.** Build in the slice order in §11. Each slice ends with the
   app running on a real device.

## 2. The user and the goal (seed data — make all of it editable in Settings)

- Male, 20s, 5'7", ~74 kg. Goal weight ~68 kg.
- Program goal: **lose fat and build muscle at the same time (recomp)** while
  improving overall health. Returning after a ~2-week training gap (Nov 2026).
- Daily targets:
  - Calories: **~2,200 kcal/day** (deficit; adjustable — see calorie auto-adjust in F6)
  - Protein: **150 g/day** (acceptable range 140–150)
  - Fat: 60–70 g/day (never below 60)
  - Carbs: remainder (~240–260 g)
  - Steps: 10,000/day · Sleep: ≥ 7.5 h
- Dietary rules (hard constraints in food features):
  - **Chicken and eggs are the only meats. No pork, no beef, ever.**
  - Dislikes yogurt/dairy generally; milk + Bournvita is the one accepted
    dairy drink. No other liquid calories.
- Staple meals (seed as one-tap quick-add templates with macros):
  - 3-egg omelette + veggies + 2 toast — ~430 kcal, 24 g protein
  - 200 g chicken breast + 1.5 cups cooked rice + vegetables — ~650 kcal, 55 g
  - 200 g chicken thighs + potatoes + big salad — ~700 kcal, 50 g
  - Glass of milk + Bournvita — ~250 kcal, 10 g
- Sedentary desk job (~9 h sitting) — daily movement matters as much as sessions.

## 3. Training program (seed data — programs are data, not code)

Current direction: **4-day Upper/Lower split.** Same muscle group is never
trained on consecutive days; each group is trained 2×/week, ~72 h apart.

| Day | Session |
|---|---|
| Mon | Upper A |
| Tue | Lower A |
| Wed | Rest — steps; optional easy Zone 2 (user's choice, not prescribed) |
| Thu | Upper B |
| Fri | Lower B |
| Sat | Rest — optional 15-min incline-walk finishers happen on lifting days |
| Sun | Rest |

- **Upper A:** DB bench press, lat pulldown, overhead DB press, seated cable row
- **Upper B:** incline DB press, bent-over DB row, lat pulldown variation, farmer's carry
- **Lower A:** goblet squat or leg press, DB Romanian deadlift, walking lunges, plank
- **Lower B:** leg press or split squats, hip thrust, hamstring work, core
- Default loading: 3 sets × 10–12 reps unless the exercise entry says otherwise.
  Progression rule: when all sets finish with 2+ reps in reserve, add the
  smallest weight increment next session.
- 15-min incline treadmill walk finisher (8–10% incline, conversational pace)
  after two lifting days per week.
- Deload every 4–6 weeks: same exercises, ~60% load / half volume, one week.
- The previous program (Mon/Thu full-body + Wed/Sat Zone 2 cardio) is the
  historical baseline; keep the data model able to hold both shapes.

## 4. Design direction — use Mobbin MCP first

**Instruction to Claude Code:** you have access to the **Mobbin MCP**. Before
building or restyling any screen, search Mobbin for reference flows from the
best existing fitness apps and adapt their *general UI schemes* — layout,
hierarchy, interaction patterns, information density. Do not copy brand assets,
illustrations, copy text, or proprietary iconography. Patterns yes, pixels no.

Reference apps and what to steal from each:

- **Cal AI** — camera-first food logging flow, the scan → result → confirm
  sequence, macro result cards, portion adjustment UI, streak surfaces.
  Mobbin searches: "Cal AI food scan", "Cal AI meal result", "calorie tracker onboarding results".
- **MyFitnessPal / Cronometer** — diary list structure, quick-add and
  recent-foods patterns, barcode scan flow.
- **Whoop / Oura** — readiness/recovery score presentation, HRV & sleep
  detail screens, "strain vs recovery" balance visuals.
- **Strong / Hevy** — workout history lists, exercise history & PR views,
  clean set tables (for the top-set log and history screens).
- **Apple Fitness / Apple Health** — rings, trend cards, summary tab layout.
  Match native iOS conventions first; this app should feel like a system app.

General UI rules:

- 4 tabs: **Today · Train · Eat · Trends** (+ Settings inside Today or a gear).
- Cards, not walls of text. Every number on Today is one glance.
- Protein ring is the hero of the Eat tab; readiness score is the hero of Today.
- Dark-mode-first polish, SF Symbols only, Dynamic Type respected.
- Motion: subtle. Numbers animate; screens don't bounce.


## 5. Features

### F1 — Today (dashboard)
- Readiness score card (F5) with today's verdict.
- Today's session card: what the program says (e.g. "Upper A — 4 exercises"),
  with **Send to Watch** (WorkoutKit, F2) and the best-practice summary.
- Activity so far: steps, active energy, exercise minutes (HealthKit).
- Nutrition so far: calorie + protein rings vs targets; tap → Eat tab.
- Sleep last night: duration + consistency note.
- One-line AI-style summary at top (rule-based in v1; Foundation Models in F7):
  e.g. "Slept 7h40. Legs fresh. Upper A today — protein is 40 g behind pace."

### F2 — Train (management, not recording)
- Week view of the program (§3) with planned vs. completed state per day.
- **Planned vs. done:** match EventKit calendar training blocks against
  HealthKit workouts (type + day). Weekly adherence % and streak.
- **WorkoutKit scheduling:** build each session as a `CustomWorkout`
  (interval blocks for finishers; heart-rate zone targets for any Zone 2 work)
  and schedule it to the Watch Workout app. This is the only "workout
  creation" in the app — execution and recording stay in Apple's app.
- **Post-workout debrief** (from HealthKit, via background delivery): duration,
  active energy, HR avg/max, **time-in-zone breakdown** — including Zone 2
  verification on cardio (flag if most of the session drifted into Zone 3).
  Compare with the previous same-type session ("6 min longer, HR avg −3 bpm").
- **Exercise library & best practices:** seeded from free-exercise-db (§10).
  Each exercise card shows: demo images, step-by-step instructions, primary /
  secondary muscles, equipment, plus an app-curated layer: **key cues** and
  **common mistakes** (seed these for the ~15 program exercises first, e.g.
  goblet squat — chest tall, hips back; RDL — soft knees, hips to the wall).
- **Top-set quick log (the one manual training input):** Apple records no
  sets/reps/weights, so after a session the user gets a notification action /
  20-second in-app form: per exercise, top-set weight × reps. This powers the
  progression view ("bench: 20 kg × 11 → target 22.5 kg") and is exported (§9).

### F3 — Eat (nutrition)
- Day diary grouped by meal; totals header with calorie/protein/fat/carb bars.
- **Quick-add staples** (§2) as one-tap rows — the primary logging path.
- **Barcode scan** via Open Food Facts API; **search** via USDA FoodData
  Central API (whole foods: chicken, eggs, rice). Cache results locally.
- Manual custom food + portion scaling by grams.
- Recents & repeat-yesterday.
- **HealthKit write-back:** every logged meal writes dietary energy, protein,
  carbohydrate, fat (and water when logged) samples to HealthKit, so nutrition
  data lives in Apple Health even if this app is deleted.
- Optional v2: text/photo → macros parsing with on-device Foundation Models
  first ("2 eggs and toast"), Claude API only if the user adds their own key.

### F4 — Recovery inputs
- **Morning check-in (≤10 seconds):** sleep is read automatically; the user
  taps soreness per muscle group (none / mild / sore) and energy (1–5).
  Model it like a CareKit-style symptom task — a daily habit surface, not a form.
- Water quick-log (writes to HealthKit).

### F5 — Readiness engine (rules-based v1; pure functions, unit-tested)
Inputs: sleep duration & consistency (7-day), HRV vs 30-day baseline, resting
HR vs baseline, yesterday's training load (duration × HR from HealthKit),
soreness check-in, days since last session per muscle group.
Output: score 0–100 + verdict, one of:
- **Train as planned** · **Train, cap intensity** · **Swap today with the next
  session** (e.g. legs still sore on Lower day → do Upper) · **Active recovery**
Rules must respect the program constraint: never recommend training a muscle
group that was trained < 48 h ago or is marked sore. Every verdict shows its
top 2 reasons ("HRV −18% vs baseline", "slept 6h10").

### F6 — Trends
- **Weight:** daily points + **7-day weekly average** line (the number that
  matters), rate of change kg/week, distance to 68 kg.
- **Calorie auto-adjust (weekly, suggest-only):** apply the program rules —
  avg loss < 0.3 kg/week for 2 weeks → suggest 2,000 kcal; > 0.8 kg/week →
  suggest 2,400 kcal. Never change targets silently; one-tap accept.
- **Load management:** weekly training load (Σ duration × intensity proxy),
  acute:chronic ratio band display; spike warning after layoffs.
- **Deload prompt** when week 5–6 of a block is reached.
- VO2 max trend, resting HR trend, sleep-duration/consistency trends,
  protein hit-rate (% days ≥ 140 g), adherence % (F2). Swift Charts throughout.

### F7 — Weekly review (Sunday evening)
Auto-generated card + notification: sessions done vs planned, avg protein,
weight trend + any calorie suggestion, sleep average, one win, one focus for
next week. On-device summary text via Foundation Models (fallback: templates).

### F8 — System surfaces
- **Widgets (WidgetKit):** Today widget (session + readiness), Eat widget
  (protein ring), small streak widget.
- **Live Activity (ActivityKit):** optional gym-day card on training evenings
  (session name, Send-to-Watch state) — keep minimal.
- **App Intents / Siri / Shortcuts:** "Log my omelette", "Log water",
  "What's my readiness?", "Log top set". Voice logging is a core habit feature.
- **Notifications (smart only):** morning readiness; protein shortfall at ~8 pm
  if fixable ("62 g to go — a chicken dinner closes it"); training-day 6:30 pm
  check if no workout has landed in HealthKit; Sunday review. Nothing else.

## 6. HealthKit integration map

Read (with background delivery + observer queries where marked *):
`HKWorkout` *, active/resting energy *, steps *, exercise minutes, stand hours,
heart rate *, resting HR, HRV (SDNN), VO2 max, heart-rate recovery, sleep
analysis *, respiratory rate, SpO2, body mass *, body fat %, waist
circumference, dietary water.

Write: dietary energy / protein / carbohydrate / fat / water (from F3), body
mass and waist (manual entries), and nothing else in v1.

Derived mirrors stored in SwiftData (needed for trends + export, §9):
`WorkoutMirror` (id, type, start/end, duration, activeEnergy, hrAvg, hrMax,
timeInZones, source=Apple Workout), `SleepNight`, `WeightPoint`,
`ReadinessSnapshot`. Recompute mirrors idempotently from HealthKit UUIDs.

## 7. Data model (SwiftData; all app-owned entities are exportable)

- `Program` → `ProgramDay` (weekday, kind) → `SessionTemplate` →
  `SessionExercise` (exerciseId, sets, reps, order, finisher flag)
- `Exercise` (id from free-exercise-db, name, muscles, equipment, instructions,
  imageRefs, cues, commonMistakes)
- `FoodItem` (name, brand, kcal/protein/fat/carb per 100 g, source:
  staple|OFF|USDA|custom, barcode?)
- `MealLog` (date, meal, foodItem, grams, computed macros)
- `TopSetLog` (date, exerciseId, weightKg, reps, sessionType)
- `CheckIn` (date, soreness per muscle group, energy 1–5)
- `ReadinessSnapshot` (date, score, verdict, reasons[])
- `GoalSettings` (targets from §2, program start date, deload cadence)
- `ExportManifest` (schemaVersion, exportedAt, recordCounts)


## 8. Tech stack & project structure

- SwiftUI, **iOS 26 deployment target** (personal device; unlocks Foundation
  Models). SwiftData for persistence (private CloudKit mirroring optional).
- Frameworks: HealthKit, WorkoutKit, EventKit, WidgetKit, ActivityKit,
  App Intents, UserNotifications, Foundation Models, Swift Charts, AVFoundation
  (barcode camera) or VisionKit DataScanner.
- No backend, no third-party SDKs, no analytics. API keys (USDA demo key,
  optional Claude key) live in Keychain / local config, **never in the repo**.
- Units: kg, kcal, grams everywhere. Dates: ISO 8601 in all exports; the app
  reasons in the user's timezone (America/Toronto).
- Engines (readiness F5, trends F6, calorie rules) are pure Swift functions
  over value types and **must ship with unit tests** — they are the product.

## 9. Export & Muse connectivity (core requirement)

The user wants to ask Muse (chat / Claude Code) "how is my training going?"
and get an answer from his real logs. **HealthKit is not reachable from
outside the phone**, so this app is the bridge. Design everything below as
first-class, not a settings-page extra.

### 9.1 Export formats (all app-owned + mirrored data, §6–§7)
- **`export.json`** — full export, one file, top-level `schemaVersion`,
  `exportedAt`, and arrays per entity (workouts, sleep, weight, meals,
  topSets, checkins, readiness, program, settings). Stable field names;
  breaking changes bump `schemaVersion`. Document the schema in
  `EXPORT_SCHEMA.md` in the repo and keep it in sync.
- **CSV per entity** — for spreadsheets.
- **`daily-log.md`** — append-only, human- and LLM-readable daily journal.
  One block per day, written for an AI reader: plain facts, units inline.

```markdown
## 2026-11-09 (Mon)
- Readiness: 82 — train as planned (slept 7h42; HRV near baseline)
- Workout (Apple Workout): Strength, 19:04–19:55, 51 min, 368 kcal, HR 120 avg / 150 max
- Top sets: goblet squat 24 kg × 12 · DB bench 20 kg × 11 · RDL 22 kg × 12
- Food: 2,180 kcal · protein 148 g / 150 g · fat 64 g · carbs 248 g
  - Lunch: chicken breast 200 g + rice — 650 kcal, 55 g protein
- Sleep (last night): 7h42, resting HR 58, HRV 41 ms
- Weight: 73.6 kg (7-day avg 73.9, −0.4 kg/week) · Steps: 10,240
```

- **`summary-latest.md`** — rolling 28-day summary, overwritten each export:
  targets, current weekly averages, adherence, last 14 days as a small table,
  open suggestions (e.g. pending calorie adjustment). This is the file an AI
  reads first — keep it under ~150 lines.

### 9.2 Auto-export (the set-and-forget path)
- User picks an **iCloud Drive folder** once (security-scoped bookmark).
- App writes `export.json`, `daily-log.md` (append), `summary-latest.md`
  nightly and on demand from Settings. Atomic writes (temp file + rename).
- Result: the same files are readable on the user's Mac by Claude Code, by an
  MCP server, or by hand. Manual share-sheet export also available.

### 9.3 MCP companion server (Slice 9 — `recomp-mcp/`)
- Small TypeScript (or Python) MCP server in this repo, **stdio transport,
  read-only**, reading the export folder (local path via env var).
- Tools (compact JSON in/out, include `schemaVersion` in every response):
  - `get_today()` — readiness, today's session, nutrition so far, last sleep
  - `get_workouts({from, to})` — mirrored workouts with HR/zone data
  - `get_nutrition({from, to})` — daily totals, optional meal detail
  - `get_weight_trend({weeks})` — points, weekly averages, rate of change
  - `get_readiness({from, to})` — scores, verdicts, reasons
  - `get_checkins({from, to})` — soreness + energy
  - `get_exercise_history({exercise})` — top-set progression over time
- Security: no network listener by default; if HTTP transport is ever added,
  require a bearer token from env/Keychain — never commit secrets.
- Acceptance test: with *only* these tools connected, Muse answers "how is
  my training going this month?" accurately (sessions vs plan, protein,
  weight trend) without the user pasting anything.

## 10. References & data sources (respect licenses)

- **free-exercise-db** — https://github.com/yuhonas/free-exercise-db
  Public domain (Unlicense). Seed the library from `dist/exercises.json`
  (https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json)
  + its images; bundle locally, no runtime dependency.
- **Cladiron (Parso workout app)** — open-source SwiftUI/SwiftData strength
  app with HealthKit: https://github.com/startupstartupapp/parso-workout-ios-app/blob/HEAD/CLAUDE.md
  Read for architecture patterns; check its LICENSE before reusing any code.
- **OutRun** — https://github.com/timfraedrich/OutRun — HealthKit workout
  patterns. GPL: read-only reference, do not copy code.
- **wger** — https://github.com/wger-project/wger — AGPL. Data/API design
  reference only; do not embed code or server components.
- **OpenNutriTracker** — nutrition UX reference (Flutter), not a code base.
- **Open Food Facts API** — barcodes/packaged food (ODbL: add attribution in
  Settings → Credits). **USDA FoodData Central API** — whole foods (CC0).
- Apple: HealthKit & WorkoutKit docs; WWDC "Build custom workouts with
  WorkoutKit"; Foundation Models framework docs.

## 11. Build plan (slices — finish one before starting the next)

Working agreements: read this whole spec before writing code. Mobbin MCP
before any UI work (§4). After each slice: build, run on the user's device,
commit, and note what changed at the bottom of this file.

0. **Scaffold + design pass.** Project, 4-tab skeleton, design tokens from
   Mobbin references (§4). Done = empty app on device that feels native.
1. **HealthKit read + Today v1.** Permissions flow, mirrors (§6), Today with
   activity, last workout, last sleep. Done = Today matches Apple Health.
2. **Export engine.** §9.1–9.2 complete (JSON, CSV, daily-log.md,
   summary-latest.md, iCloud auto-export). Done = Muse can read a real week
   of data from the exported files. *(Early on purpose: data access is the
   point of this app.)*
3. **Exercise library.** Seed import (§10), library search, detail cards with
   cues/common mistakes for the program exercises.
4. **Train.** Program data (§3), week view, planned-vs-done (EventKit +
   HealthKit), WorkoutKit send-to-Watch, post-workout debrief with zones,
   top-set quick log.
5. **Eat.** Staples quick-add, diary, barcode (OFF), search (USDA), manual
   foods, HealthKit write-back, protein/calorie rings.
6. **Check-in + readiness.** Morning check-in (F4), readiness engine (F5)
   with unit tests, verdicts on Today.
7. **Trends + review.** Weight weekly average, calorie auto-adjust suggestions,
   load/deload logic, VO2/RHR/sleep trends, Sunday weekly review (F7).
8. **System surfaces.** Widgets, App Intents/Siri, smart notifications,
   optional Live Activity (F8).
9. **MCP server.** `recomp-mcp` per §9.3 + the acceptance test.

## 12. Non-goals & open decisions

Non-goals: workout recording/GPS, social features, accounts, Android/web,
App Store release, medical advice or diagnosis (readiness is training
guidance), coaching anyone but the user. Food suggestions must always respect
§2 dietary rules — never surface pork/beef products as suggestions.

Open decisions (ask the user; defaults in brackets): final app name
[Recomp], iOS target [26], MCP timing [Slice 9, after exports prove out],
top-set log [on], CloudKit sync [off in v1 — iCloud Drive export covers it].

---

*Changelog: 2026-11-03 — spec created from product discussion (Health & Gym
chat): Apple records, app manages; Upper/Lower split; export + MCP as core.*
