/**
 * Invented data. No real health data ever lands in this repo (CLAUDE.md), and
 * rollups carry totals only, so there are no food rows here to break the
 * dietary rules with.
 *
 * `wins` are computed here the way docs/EXPORT_SCHEMA.md says the device
 * computes them, because the Worker must never recompute them: the fixture is
 * standing in for the phone.
 */
import type { DayRollup } from "../src/contract";
import { addDays, isoWeekday } from "../src/dates";
import documentedExample from "./export-schema-example.json" with { type: "json" };

/** The seeded `goalSettings.targets` from migration 0002. */
export const TARGETS = {
  kcal: 2200,
  proteinG: 150,
  proteinMinG: 140,
  steps: 10000,
  sleepMinutes: 450,
};

export const TIMEZONE = "America/Toronto";

/** The `DayRollup` printed in docs/EXPORT_SCHEMA.md §1, verbatim. */
export const DOCUMENTED_EXAMPLE = documentedExample as unknown as DayRollup;

/** The last day of the fixture series, and the documented example's date. */
export const LAST_DAY = "2026-11-03";

/** Monday = upperA … Sunday = rest, exactly the §2.2 program. */
const WEEK: Array<DayRollup["training"]["sessionPlanned"]> = [
  "upperA",
  "lowerA",
  "rest",
  "upperB",
  "lowerB",
  "rest",
  "rest",
];

const EXERCISES: Record<string, string[]> = {
  upperA: ["DB_Bench_Press", "Lat_Pulldown", "Overhead_DB_Press", "Seated_Cable_Row"],
  upperB: ["Incline_DB_Press", "Chin_Up", "DB_Lateral_Raise", "Face_Pull"],
  lowerA: ["Goblet_Squat", "Romanian_Deadlift", "Leg_Press", "Standing_Calf_Raise"],
  lowerB: ["Bulgarian_Split_Squat", "Hip_Thrust", "Leg_Curl", "Hanging_Leg_Raise"],
};

/** mulberry32 — the series must be identical on every run. */
function rng(seed: number): () => number {
  let state = seed + 0x6d2b79f5;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function offsetStamp(date: string, time: string): string {
  // Fixture dates sit either side of the DST change; both offsets are valid
  // ISO 8601, and the contract only requires that an offset is present.
  const offset = date >= "2026-11-01" ? "-05:00" : "-04:00";
  return `${date}T${time}${offset}`;
}

type Overrides = {
  skipCheckIn?: boolean;
  missSession?: boolean;
};

export function makeRollup(
  date: string,
  index: number,
  overrides: Overrides = {},
): DayRollup {
  const random = rng(index * 7919);
  const sessionPlanned = WEEK[isoWeekday(date) - 1] ?? "rest";
  const isTrainingDay = sessionPlanned !== "rest";
  const sessionDone = isTrainingDay && !overrides.missSession;

  const proteinG = Math.round(118 + random() * 48);
  const steps = Math.round(7_600 + random() * 5_200);
  const asleepMinutes = Math.round(398 + random() * 98);
  const restingHrBpm = Math.round(54 + random() * 8);
  const hrAvgBpm = Math.round(112 + random() * 22);
  const durationMinutes = Math.round(42 + random() * 22);

  const weightKg = Math.round((75.2 - index * 0.0125 + (random() - 0.5) * 0.6) * 10) / 10;
  const weightAvg7Kg = Math.round((75.2 - index * 0.0125) * 10) / 10;

  const checkIn = overrides.skipCheckIn
    ? null
    : {
        energy: 1 + Math.floor(random() * 5),
        soreness: {
          chest: sessionPlanned === "upperA" ? ("sore" as const) : ("none" as const),
          back: isTrainingDay ? ("mild" as const) : ("none" as const),
          shoulders: "none" as const,
          arms: random() > 0.7 ? ("mild" as const) : ("none" as const),
          quads: sessionPlanned === "lowerA" ? ("sore" as const) : ("none" as const),
          hamstrings: sessionPlanned === "lowerB" ? ("sore" as const) : ("mild" as const),
          glutes: "none" as const,
          core: "none" as const,
        },
      };

  const score = Math.round(52 + random() * 44);
  const readiness = checkIn
    ? {
        score,
        verdict:
          score >= 75
            ? ("trainAsPlanned" as const)
            : score >= 62
              ? ("capIntensity" as const)
              : score >= 50
                ? ("swapSession" as const)
                : ("activeRecovery" as const),
        reasons: [`slept ${Math.floor(asleepMinutes / 60)}h${asleepMinutes % 60}`],
      }
    : null;

  const wins = {
    // `session` is true when the session was done, or when rest was planned and
    // no workout landed (docs/EXPORT_SCHEMA.md §1).
    session: sessionDone || sessionPlanned === "rest",
    protein: proteinG >= TARGETS.proteinMinG,
    steps: steps >= TARGETS.steps,
    sleep: asleepMinutes >= TARGETS.sleepMinutes,
    total: 0,
  };
  wins.total = [wins.session, wins.protein, wins.steps, wins.sleep].filter(Boolean)
    .length;

  return {
    date,
    timezone: TIMEZONE,
    updatedAt: offsetStamp(date, "23:05:00"),
    nutrition: {
      kcal: Math.round(1_880 + random() * 520),
      proteinG,
      fatG: Math.round(58 + random() * 18),
      carbsG: Math.round(196 + random() * 92),
      waterMl: Math.round(1_900 + random() * 1_100),
    },
    activity: {
      steps,
      activeEnergyKcal: Math.round(420 + random() * 320),
      exerciseMinutes: Math.round(18 + random() * 48),
      standHours: 8 + Math.floor(random() * 6),
    },
    sleep: {
      asleepMinutes,
      inBedMinutes: asleepMinutes + Math.round(18 + random() * 26),
      consistencySd7Minutes: Math.round(20 + random() * 30),
    },
    vitals: {
      restingHrBpm,
      hrvSdnnMs: Math.round(32 + random() * 22),
      vo2Max: Math.round((42 + random() * 3) * 10) / 10,
      respiratoryRate: Math.round((13 + random() * 2) * 10) / 10,
      spo2Pct: 95 + Math.floor(random() * 4),
    },
    body: {
      weightKg,
      weightAvg7Kg,
      rateKgPerWeek: -0.4,
      bodyFatPct: null,
      waistCm: null,
    },
    training: {
      sessionPlanned,
      sessionDone,
      loadAu: sessionDone
        ? Math.round(durationMinutes * (hrAvgBpm / restingHrBpm) * 10) / 10
        : null,
      workouts: sessionDone
        ? [
            {
              healthKitId: `FIXTURE-0000-0000-0000-${String(index).padStart(12, "0")}`,
              type: "traditionalStrengthTraining",
              startedAt: offsetStamp(date, "19:04:00"),
              endedAt: offsetStamp(date, "19:55:00"),
              durationMinutes,
              activeEnergyKcal: Math.round(280 + random() * 160),
              hrAvgBpm,
              hrMaxBpm: hrAvgBpm + Math.round(18 + random() * 18),
              timeInZonesMinutes: { z1: 4, z2: 22, z3: 18, z4: 6, z5: 1 },
              source: "Apple Workout",
            },
          ]
        : [],
      topSets: sessionDone
        ? (EXERCISES[sessionPlanned] ?? []).slice(0, 2).map((exerciseId, slot) => ({
            exerciseId,
            // A slow climb, so a history read has a visible progression.
            weightKg: 18 + slot * 4 + Math.floor(index / 28) * 2.5,
            reps: 10 + Math.floor(random() * 3),
          }))
        : [],
    },
    checkIn,
    readiness,
    wins,
  };
}

/**
 * `days` contiguous rollups ending the day before {@link LAST_DAY}, with the
 * documented example appended as the final day. 126 days covers the 17-week
 * grid plus a week of slack.
 */
export function seedSeries(days = 126): DayRollup[] {
  const generated = Array.from({ length: days - 1 }, (_, index) => {
    const date = addDays(LAST_DAY, -(days - 1) + index);
    return makeRollup(date, index, {
      skipCheckIn: index % 9 === 0,
      missSession: index % 11 === 0,
    });
  });
  return [...generated, DOCUMENTED_EXAMPLE];
}
