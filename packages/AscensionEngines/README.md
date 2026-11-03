# AscensionEngines

Readiness (spec §F5), trends (spec §F6) and the calorie rules. Spec §8 calls these the
product. Depends on `AscensionCore` and nothing else.

## The four properties

1. **Pure.** No `Date()`, no `Calendar.current`, no singletons, no caches. The clock
   arrives as `EngineClock`; day arithmetic is integer Julian-day maths.
2. **`null` is not zero.** An absent signal leaves the score's weighted mean and narrows
   `confidence`. It never scores zero.
3. **Legality is not negotiable.** `SessionLegality` decides *what* may be trained;
   the score only decides *how hard*. No score unlocks a region inside its 48 h window.
4. **Suggest-only.** Nothing here writes. `CalorieSuggestion` is a value, not a mutation.

## Readiness

```swift
let input = ReadinessHistory.input(history: rollups, clock: clock,
                                   program: program, goals: goals)
let assessment = ReadinessEngine.assess(input)

assessment.score             // 0...100
assessment.verdict           // trainAsPlanned | capIntensity | swapSession | activeRecovery
assessment.reasons           // exactly 2 plain facts with units
assessment.confidence        // high | moderate | low
assessment.suggestedSession  // non-nil exactly when verdict == .swapSession
assessment.blockedRegions    // why the plan cannot run as written
assessment.rollup            // the ReadinessRollup the contract syncs
```

`ReadinessHistory.input` derives the 30-day baselines, yesterday's load and the
last-trained stamps from synced `DayRollup`s. Build the input by hand only in tests.

## Trends

```swift
let report = TrendsEngine.report(history: rollups, goals: goals,
                                 program: program, clock: clock)

report.weight.latestAverageKg     // the 7-day average — the number that matters
report.weight.rateKgPerWeek       // negative while losing
report.weight.kgToGoal
report.calorieSuggestion          // nil unless a rule fires; never applied for you
report.load.acuteChronicRatio     // nil when there is no chronic load
report.load.band                  // detraining | optimal | caution | highRisk
report.load.spikeAfterLayoff
report.deload                     // active | notDue | due | overdue
report.habits.proteinHitRatePct   // % of days in the window at 140 g or more
report.habits.adherencePct        // nil when the window planned no sessions
```

The sub-engines — `WeightTrendEngine`, `CalorieAdjustEngine`, `LoadTrendEngine`,
`DeloadDetector`, `HabitTrendsEngine` — are public and usable on their own.

## Three things that will bite you

1. **`yesterdayLoadAu: 0` and `nil` are different.** Zero is a rest day and scores as
   full recovery; `nil` is unmeasured and drops the term. Pass the right one, or let
   `ReadinessHistory` do it.
2. **`loadAu` is read as stored, never recomputed.** It is defined once, in
   `docs/EXPORT_SCHEMA.md` §1 and `TrainingRollup.loadAu`.
3. **A rest day is always `trainAsPlanned`.** Nothing is prescribed, so there is nothing
   to cap or stand down from. The score and reasons still surface.

## Tests

```
swift test --package-path packages/AscensionEngines
```

Boundaries are tested at, just below and just above: 48 h, 0.3 and 0.8 kg/week, 140 g
protein, 7.5 h sleep, the ACWR bands and the deload cadence week. A 2,880-case grid
asserts the invariants that must hold for every input — score in range, exactly two
reasons, and never a recommendation to train a region that may not be trained.
