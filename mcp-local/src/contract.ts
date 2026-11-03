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
  sessions: z.record(
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
