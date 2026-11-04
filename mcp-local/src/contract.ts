/**
 * The data contract, in code. `docs/EXPORT_SCHEMA.md` is the prose; this file is
 * the only place the field names live on the edge, so the app and the Worker
 * cannot drift. Any change here is a `schemaVersion` bump there, in the same PR.
 *
 * Units are fixed: kg, kcal, grams, millilitres, minutes, bpm, ms.
 * `null` means *not measured*; it never means zero.
 */
import { z } from "zod";

export const SCHEMA_VERSION = 1;

/** `YYYY-MM-DD` in the user's timezone. */
export const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "expected a YYYY-MM-DD date");

/** ISO 8601 with offset — `2026-11-03T23:05:00-05:00` or a `Z`. */
export const isoTimestamp = z
  .string()
  .regex(
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/,
    "expected an ISO 8601 timestamp with offset",
  );

/** A measurement that may be absent. Present key, `null` value — never 0. */
const measured = () => z.number().nullable();

export const sessionKinds = [
  "upperA",
  "upperB",
  "lowerA",
  "lowerB",
  "fullBody",
  "zone2",
  "rest",
] as const;
export const SessionKind = z.enum(sessionKinds);

export const verdicts = [
  "trainAsPlanned",
  "capIntensity",
  "swapSession",
  "activeRecovery",
] as const;
export const Verdict = z.enum(verdicts);

export const sorenessLevels = ["none", "mild", "sore"] as const;
export const SorenessLevel = z.enum(sorenessLevels);

export const muscleGroups = [
  "chest",
  "back",
  "shoulders",
  "arms",
  "quads",
  "hamstrings",
  "glutes",
  "core",
] as const;

export const actors = ["muse", "device", "system"] as const;
export const Actor = z.enum(actors);

export const documentKeys = ["goalSettings", "program", "flags"] as const;
export const DocumentKey = z.enum(documentKeys);

export const mealSlots = ["breakfast", "lunch", "dinner", "snack"] as const;

/* -------------------------------------------------------------- DayRollup -- */

export const Nutrition = z.strictObject({
  kcal: measured(),
  proteinG: measured(),
  fatG: measured(),
  carbsG: measured(),
  waterMl: measured(),
});

export const Activity = z.strictObject({
  steps: measured(),
  activeEnergyKcal: measured(),
  exerciseMinutes: measured(),
  standHours: measured(),
});

export const Sleep = z.strictObject({
  asleepMinutes: measured(),
  inBedMinutes: measured(),
  consistencySd7Minutes: measured(),
});

export const Vitals = z.strictObject({
  restingHrBpm: measured(),
  hrvSdnnMs: measured(),
  vo2Max: measured(),
  respiratoryRate: measured(),
  spo2Pct: measured(),
});

export const Body = z.strictObject({
  weightKg: measured(),
  weightAvg7Kg: measured(),
  rateKgPerWeek: measured(),
  bodyFatPct: measured(),
  waistCm: measured(),
});

export const TimeInZonesMinutes = z.strictObject({
  z1: measured(),
  z2: measured(),
  z3: measured(),
  z4: measured(),
  z5: measured(),
});

export const Workout = z.strictObject({
  healthKitId: z.string().min(1),
  /**
   * The HealthKit workout type, e.g. `traditionalStrengthTraining`. Left open:
   * `docs/EXPORT_SCHEMA.md` declares no closed set, and HealthKit's own list
   * grows with each OS release.
   */
  type: z.string().min(1),
  startedAt: isoTimestamp,
  endedAt: isoTimestamp,
  durationMinutes: measured(),
  activeEnergyKcal: measured(),
  hrAvgBpm: measured(),
  hrMaxBpm: measured(),
  timeInZonesMinutes: TimeInZonesMinutes,
  source: z.string().min(1),
});

export const TopSet = z.strictObject({
  /** A free-exercise-db id, e.g. `Goblet_Squat`. */
  exerciseId: z.string().min(1),
  weightKg: z.number(),
  reps: z.number().int(),
});

export const Training = z.strictObject({
  sessionPlanned: SessionKind.nullable(),
  sessionDone: z.boolean(),
  loadAu: measured(),
  workouts: z.array(Workout),
  topSets: z.array(TopSet),
});

export const Soreness = z.strictObject(
  Object.fromEntries(muscleGroups.map((group) => [group, SorenessLevel])) as {
    [G in (typeof muscleGroups)[number]]: typeof SorenessLevel;
  },
);

export const CheckIn = z.strictObject({
  energy: z.number().int().min(1).max(5),
  soreness: Soreness,
});

export const Readiness = z.strictObject({
  score: z.number().int().min(0).max(100),
  verdict: Verdict,
  reasons: z.array(z.string()),
});

export const Wins = z.strictObject({
  session: z.boolean(),
  protein: z.boolean(),
  steps: z.boolean(),
  sleep: z.boolean(),
  total: z.number().int().min(0).max(4),
});

/**
 * One per day. The unit of sync, and the unit most read tools return.
 * `strictObject` throughout: an unknown field is a contract divergence, so it
 * fails loudly at `POST /v1/ingest` instead of being silently dropped.
 */
export const DayRollup = z.strictObject({
  date: isoDate,
  timezone: z.string().min(1),
  updatedAt: isoTimestamp,

  nutrition: Nutrition,
  activity: Activity,
  sleep: Sleep,
  vitals: Vitals,
  body: Body,
  training: Training,

  /** Absent on a day with no morning check-in. */
  checkIn: CheckIn.nullable(),
  /** Absent when the engine had nothing to score. */
  readiness: Readiness.nullable(),

  /** Computed on device and stored, never recomputed here. */
  wins: Wins,
});

export type DayRollup = z.infer<typeof DayRollup>;
export type Workout = z.infer<typeof Workout>;
export type TopSet = z.infer<typeof TopSet>;
export type Wins = z.infer<typeof Wins>;
export type MuscleGroup = (typeof muscleGroups)[number];

/* ------------------------------------------------------------- ingest API -- */

/**
 * `POST /v1/ingest` takes `{ rollups: [...] }`. A bare array is normalised into
 * that envelope before parsing, so the phone may send either; parsing the one
 * shape keeps error paths precise (`rollups.3.training.sessionPlanned`) instead
 * of a union's nested noise.
 */
export const IngestEnvelope = z.strictObject({
  schemaVersion: z.literal(SCHEMA_VERSION).optional(),
  rollups: z.array(DayRollup),
});

/* --------------------------------------------------------------- documents -- */

/**
 * Document *bodies*. `version`, `updatedAt` and `updatedBy` are columns on the
 * `documents` table, not part of the body, and are composed back on read — so
 * there is exactly one copy of each.
 */

export const Targets = z.strictObject({
  kcal: z.number(),
  proteinG: z.number(),
  proteinMinG: z.number(),
  fatMinG: z.number(),
  fatMaxG: z.number(),
  steps: z.number(),
  sleepMinutes: z.number(),
});

export const GoalSettingsBody = z.strictObject({
  targets: Targets,
  body: z.strictObject({
    goalWeightKg: z.number(),
    heightCm: z.number(),
  }),
  programStartDate: isoDate,
  deloadEveryWeeks: z.number().int(),
  timezone: z.string().min(1),
  dietaryRules: z.strictObject({
    excludedMeats: z.array(z.string()),
    allowedDairy: z.array(z.string()),
    noLiquidCalories: z.boolean(),
  }),
});

export const ProgramBody = z.strictObject({
  name: z.string().min(1),
  /** Exactly 7 entries. `weekday` is ISO-8601: Monday = 1. */
  days: z
    .array(
      z.strictObject({
        weekday: z.number().int().min(1).max(7),
        kind: SessionKind,
      }),
    )
    .length(7),
  /**
   * Only the kinds the week actually plans, keyed by session kind -- `rest` has
   * no template and a program need not define every lifting split.
   *
   * `partialRecord`, not `record`: a zod 4 `record` over an enum key is
   * exhaustive, so it demanded a template for all seven kinds and rejected the
   * program docs/EXPORT_SCHEMA.md §2.2 prints. The Swift side is a partial
   * dictionary, so this is the shape the contract always described.
   */
  sessions: z.partialRecord(
    SessionKind,
    z.strictObject({
      name: z.string().min(1),
      exercises: z.array(
        z.strictObject({
          order: z.number().int(),
          exerciseId: z.string().min(1),
          sets: z.number().int(),
          repsLow: z.number().int(),
          repsHigh: z.number().int(),
          finisher: z.boolean(),
        }),
      ),
    }),
  ),
  progression: z.strictObject({
    rule: z.string().min(1),
    incrementKg: z.number(),
  }),
  finisher: z.strictObject({
    kind: z.string().min(1),
    minutes: z.number(),
    inclinePct: z.number(),
    daysPerWeek: z.number().int(),
  }),
  deload: z.strictObject({
    active: z.boolean(),
    loadFactor: z.number(),
    volumeFactor: z.number(),
  }),
});

export const FlagsBody = z.strictObject({
  remoteBridgeEnabled: z.boolean(),
  museWritesEnabled: z.boolean(),
  museWriteMode: z.enum(["apply", "propose"]),
  rawDetailSyncEnabled: z.boolean(),
  foundationModelsEnabled: z.boolean(),
});

export const documentBodies = {
  goalSettings: GoalSettingsBody,
  program: ProgramBody,
  flags: FlagsBody,
} as const;

export type DocumentKey = (typeof documentKeys)[number];
export type GoalSettingsBody = z.infer<typeof GoalSettingsBody>;
export type FlagsBody = z.infer<typeof FlagsBody>;
export type Targets = z.infer<typeof Targets>;

/* --------------------------------------------------------------- mutations -- */

/**
 * The write log's closed set of kinds (docs/EXPORT_SCHEMA.md §3), in the order
 * the table lists them. ASC-12 asked for this tuple: the kinds were the one
 * closed set that lived in prose only, so the phone's contract check had to read
 * the markdown table instead of this file.
 */
export const mutationKinds = [
  "set_targets",
  "update_program",
  "set_staples",
  "set_flag",
  "accept_suggestion",
  "log_meal",
  "log_water",
  "log_top_set",
  "log_checkin",
  "schedule_workout",
  "trigger_export",
] as const;
export const MutationKind = z.enum(mutationKinds);
export type MutationKind = (typeof mutationKinds)[number];

/**
 * Tier 1 is state the Worker owns; Tier 2 needs an API only the phone has, so a
 * Tier-2 tool may never answer anything but `pending_device_apply`
 * (docs/MUSE_CAPABILITIES.md). Mirrors `MutationKind.tier` in AscensionCore.
 */
const TIER_ONE: readonly MutationKind[] = [
  "set_targets",
  "update_program",
  "set_staples",
  "set_flag",
  "accept_suggestion",
];

export function tierOf(kind: MutationKind): 1 | 2 {
  return TIER_ONE.includes(kind) ? 1 : 2;
}

/** Spec §7 spelling: `OFF` and `USDA` are uppercase. */
export const foodSources = ["staple", "OFF", "USDA", "custom"] as const;

/**
 * The `FoodItem` of the `set_staples` payload. §3 names the type but no section
 * declares it; this is the shape AscensionCore encodes (spec §7 field for
 * field), per the ASC-2 hand-over note. Macros are per 100 g for every food so
 * portion scaling is uniform; `servingGrams` is what a one-tap staple logs.
 *
 * The four optional fields are written as explicit `null` by the device and may
 * be omitted by Muse, so both are accepted.
 */
export const FoodItem = z.strictObject({
  id: z.string().min(1),
  name: z.string().min(1),
  brand: z.string().nullable().optional(),
  kcalPer100g: z.number().min(0),
  proteinPer100g: z.number().min(0),
  fatPer100g: z.number().min(0),
  carbsPer100g: z.number().min(0),
  source: z.enum(foodSources),
  barcode: z.string().nullable().optional(),
  servingGrams: z.number().positive().nullable().optional(),
  servingName: z.string().nullable().optional(),
});

/**
 * A partial `goalSettings.targets`: only the fields Muse set are present. Every
 * target is an integer on the device (`GoalTargets` in AscensionCore), so a
 * fractional calorie target would fail to decode there — it is rejected here.
 */
export const TargetsPatch = z.strictObject({
  kcal: z.number().int().optional(),
  proteinG: z.number().int().optional(),
  proteinMinG: z.number().int().optional(),
  fatMinG: z.number().int().optional(),
  fatMaxG: z.number().int().optional(),
  steps: z.number().int().optional(),
  sleepMinutes: z.number().int().optional(),
});

export const flagKeys = [
  "remoteBridgeEnabled",
  "museWritesEnabled",
  "museWriteMode",
  "rawDetailSyncEnabled",
  "foundationModelsEnabled",
] as const;
export const museWriteModes = ["apply", "propose"] as const;

/**
 * `{ key, value }`. Split by key rather than taking `unknown`: `museWriteMode`
 * is the one flag that is not a boolean, and a `true` written to it would be a
 * document the app cannot decode.
 */
export const FlagChange = z.union([
  z.strictObject({
    key: z.literal("museWriteMode"),
    value: z.enum(museWriteModes),
  }),
  z.strictObject({
    key: z.enum([
      "remoteBridgeEnabled",
      "museWritesEnabled",
      "rawDetailSyncEnabled",
      "foundationModelsEnabled",
    ]),
    value: z.boolean(),
  }),
]);

export const StaplesPayload = z.strictObject({
  staples: z.array(FoodItem),
});

export const AcceptSuggestionPayload = z.strictObject({
  suggestionId: z.string().min(1),
});

/**
 * One line of a logged meal. `foodItemId` is absent for a food Muse described
 * rather than picked from the staples.
 */
export const MealItem = z.strictObject({
  foodItemId: z.string().min(1).nullable().optional(),
  name: z.string().min(1),
  grams: z.number().min(0),
  kcal: z.number().min(0),
  proteinG: z.number().min(0),
  fatG: z.number().min(0),
  carbsG: z.number().min(0),
});

export const LogMealPayload = z.strictObject({
  date: isoDate,
  meal: z.enum(mealSlots),
  items: z.array(MealItem).min(1),
});

/** A single sane bound: HealthKit takes millilitres, and 10 L is a typo. */
export const LogWaterPayload = z.strictObject({
  date: isoDate,
  ml: z.number().positive().max(10_000),
});

export const LogTopSetPayload = z.strictObject({
  date: isoDate,
  exerciseId: z.string().min(1),
  weightKg: z.number().min(0),
  reps: z.number().int().min(1),
});

export const LogCheckInPayload = z.strictObject({
  date: isoDate,
  energy: z.number().int().min(1).max(5),
  soreness: Soreness,
});

export const ScheduleWorkoutPayload = z.strictObject({
  date: isoDate,
  sessionKind: SessionKind,
});

export const TriggerExportPayload = z.strictObject({});

/** Payload schema per kind, so a log row can be re-validated on the way out. */
export const mutationPayloads = {
  set_targets: TargetsPatch,
  update_program: ProgramBody,
  set_staples: StaplesPayload,
  set_flag: FlagChange,
  accept_suggestion: AcceptSuggestionPayload,
  log_meal: LogMealPayload,
  log_water: LogWaterPayload,
  log_top_set: LogTopSetPayload,
  log_checkin: LogCheckInPayload,
  schedule_workout: ScheduleWorkoutPayload,
  trigger_export: TriggerExportPayload,
} as const;

/**
 * One row of the append-only log as `GET /v1/mutations` serves it
 * (docs/EXPORT_SCHEMA.md §3). `appliedAt` and `appliedResult` are explicit
 * `null` until set, never omitted.
 */
export const Mutation = z.strictObject({
  id: z.string().length(26),
  createdAt: isoTimestamp,
  actor: Actor,
  kind: MutationKind,
  payload: z.unknown(),
  appliedAt: isoTimestamp.nullable(),
  appliedResult: z.unknown().nullable(),
});

export type Mutation = z.infer<typeof Mutation>;

/**
 * `POST /v1/mutations/ack`. `appliedAt` is the *device's* instant, not the
 * Worker's: a drain that happened offline keeps the time it really happened.
 */
export const MutationAck = z.strictObject({
  schemaVersion: z.literal(SCHEMA_VERSION).optional(),
  ids: z.array(z.string().length(26)).min(1).max(500),
  appliedAt: isoTimestamp,
});

/* ------------------------------------------------------------- suggestions -- */

export const suggestionSources = ["muse", "device"] as const;
export const suggestionStatuses = ["pending", "accepted"] as const;

/**
 * Something waiting for a one-tap accept: either the §F6 calorie auto-adjust the
 * device raised, or — when `flags.museWriteMode` is `propose` — a Tier-1 write
 * Muse asked for and the Worker has not made.
 *
 * `action` is what accepting *does*. A suggestion without one can only be
 * applied on the phone (it is the phone's own, and it knows the id), so
 * `accept_suggestion` queues it rather than applying it here.
 */
export const Suggestion = z.strictObject({
  id: z.string().min(1).max(64),
  createdAt: isoTimestamp,
  source: z.enum(suggestionSources),
  /** The suggestion's own label, e.g. `calorieAdjust`. Open: §4 pins no set. */
  kind: z.string().min(1),
  /** One plain-language line, as `summary-latest.md` lists it. */
  text: z.string().min(1),
  action: z
    .strictObject({ kind: MutationKind, payload: z.unknown() })
    .nullable(),
  status: z.enum(suggestionStatuses),
  decidedAt: isoTimestamp.nullable(),
});

export type Suggestion = z.infer<typeof Suggestion>;

/** `POST /v1/suggestions` — the device handing its open suggestions up. */
export const SuggestionUpload = z.strictObject({
  schemaVersion: z.literal(SCHEMA_VERSION).optional(),
  suggestions: z
    .array(
      z.strictObject({
        id: z.string().min(1).max(64),
        createdAt: isoTimestamp,
        kind: z.string().min(1),
        text: z.string().min(1),
        action: z
          .strictObject({ kind: MutationKind, payload: z.unknown() })
          .nullable()
          .optional(),
      }),
    )
    .max(100),
});

/* ------------------------------------------------------------- write status -- */

/**
 * What a write tool answers. `pending_device_apply` is the contract's own word
 * (docs/EXPORT_SCHEMA.md §3): an assistant may never report a HealthKit write as
 * landed before the phone has applied it.
 */
export const writeStatuses = ["applied", "pending_device_apply", "proposed"] as const;
export type WriteStatus = (typeof writeStatuses)[number];

export type ProgramBody = z.infer<typeof ProgramBody>;
export type MealItem = z.infer<typeof MealItem>;
export type FoodItem = z.infer<typeof FoodItem>;
