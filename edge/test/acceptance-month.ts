/**
 * The month the acceptance run asks about (ASC-18).
 *
 * Invented data. No real health data ever lands in this repo (CLAUDE.md).
 *
 * `fixtures.ts` builds a pseudo-random 126-day series, which is right for the
 * suites that only need *some* plausible data. This month is the opposite: every
 * value is chosen so the answer can be written down. October 2026 is 31 days
 * starting on a Thursday, the program trains Mon/Tue/Thu/Fri, and exactly three
 * Fridays were missed — so "18 planned, 15 done, 3 missed" is a fact about the
 * calendar, not a number re-derived by the same code the tool uses.
 *
 * `wins` are computed here the way docs/EXPORT_SCHEMA.md says the device
 * computes them: the Worker must never recompute them, and this fixture stands
 * in for the phone.
 */
import type { DayRollup } from "../src/contract";
import { enumerateDates, isoWeekday } from "../src/dates";

type SessionKind = NonNullable<DayRollup["training"]["sessionPlanned"]>;

export const MONTH_FROM = "2026-10-01";
export const MONTH_TO = "2026-10-31";
export const TIMEZONE = "America/Toronto";

/** The §2.2 week: Mon upperA, Tue lowerA, Wed rest, Thu upperB, Fri lowerB, weekend rest. */
const WEEK: SessionKind[] = ["upperA", "lowerA", "rest", "upperB", "lowerB", "rest", "rest"];

/** Three Fridays the user did not train. Chosen, not generated. */
export const MISSED = ["2026-10-09", "2026-10-16", "2026-10-30"];

/** The protein floor and step goal the seeded `goalSettings` carries. */
const PROTEIN_FLOOR_G = 140;
const STEP_GOAL = 10_000;
const SLEEP_GOAL_MINUTES = 450;

/** Top sets, climbing, so a progression read has a provable best. */
const SQUAT_KG: Record<string, number> = {
  "2026-10-06": 20,
  "2026-10-13": 22.5,
  "2026-10-20": 25,
  "2026-10-27": 27.5,
};
const BENCH_KG: Record<string, number> = {
  "2026-10-05": 24,
  "2026-10-12": 24,
  "2026-10-19": 26,
  "2026-10-26": 26,
};

const round2 = (value: number) => Math.round(value * 100) / 100;

function day(date: string, index: number): DayRollup {
  const sessionPlanned = WEEK[isoWeekday(date) - 1] as SessionKind;
  const isTrainingDay = sessionPlanned !== "rest";
  const sessionDone = isTrainingDay && !MISSED.includes(date);

  const proteinG = isTrainingDay ? 160 : 130;
  const steps = isTrainingDay ? 11_000 : 8_000;
  // Three nights in four clear the sleep goal; every fourth does not.
  const asleepMinutes = index % 4 === 0 ? 430 : 465;
  const weightAvg7Kg = round2(75 - 0.05 * index);
  const weightKg = round2(weightAvg7Kg + [0.2, -0.1, 0][index % 3]!);

  const topSets = sessionDone
    ? [
        ...(SQUAT_KG[date] !== undefined
          ? [{ exerciseId: "Goblet_Squat", weightKg: SQUAT_KG[date]!, reps: 10 }]
          : []),
        ...(BENCH_KG[date] !== undefined
          ? [{ exerciseId: "DB_Bench_Press", weightKg: BENCH_KG[date]!, reps: 10 }]
          : []),
      ]
    : [];

  const wins = {
    // True when the session was done, or when rest was planned and none landed.
    session: sessionDone || sessionPlanned === "rest",
    protein: proteinG >= PROTEIN_FLOOR_G,
    steps: steps >= STEP_GOAL,
    sleep: asleepMinutes >= SLEEP_GOAL_MINUTES,
    total: 0,
  };
  wins.total = [wins.session, wins.protein, wins.steps, wins.sleep].filter(Boolean).length;

  return {
    date,
    timezone: TIMEZONE,
    updatedAt: `${date}T23:05:00-04:00`,
    nutrition: { kcal: 2100, proteinG, fatG: 65, carbsG: 240, waterMl: 2500 },
    activity: {
      steps,
      activeEnergyKcal: 500,
      exerciseMinutes: 30,
      standHours: 12,
    },
    sleep: { asleepMinutes, inBedMinutes: asleepMinutes + 30, consistencySd7Minutes: 25 },
    vitals: {
      restingHrBpm: 56,
      hrvSdnnMs: 45,
      vo2Max: 43.5,
      respiratoryRate: 14,
      spo2Pct: 97,
    },
    body: {
      weightKg,
      weightAvg7Kg,
      rateKgPerWeek: -0.35,
      bodyFatPct: null,
      waistCm: null,
    },
    training: {
      sessionPlanned,
      sessionDone,
      loadAu: sessionDone ? 100 : null,
      workouts: sessionDone
        ? [
            {
              healthKitId: `ACCEPT-0000-0000-0000-${date.replace(/-/g, "")}`,
              type: "traditionalStrengthTraining",
              startedAt: `${date}T19:00:00-04:00`,
              endedAt: `${date}T19:50:00-04:00`,
              durationMinutes: 50,
              activeEnergyKcal: 400,
              hrAvgBpm: 132,
              hrMaxBpm: 168,
              timeInZonesMinutes: { z1: 5, z2: 20, z3: 18, z4: 6, z5: 1 },
              source: "Apple Workout",
            },
          ]
        : [],
      topSets,
    },
    checkIn: {
      energy: isTrainingDay ? 4 : 3,
      soreness: {
        chest: "none",
        back: "none",
        shoulders: "none",
        arms: "none",
        // Sore quads only after a Lower A day — four of them in the month.
        quads: sessionPlanned === "lowerA" ? "sore" : "none",
        hamstrings: "none",
        glutes: "none",
        core: "none",
      },
    },
    readiness: {
      score: isTrainingDay ? 80 : 70,
      verdict: isTrainingDay ? "trainAsPlanned" : "capIntensity",
      reasons: ["slept near baseline"],
    },
    wins,
  };
}

/** October 2026, one rollup per day. */
export function month(): DayRollup[] {
  return enumerateDates(MONTH_FROM, MONTH_TO).map((date, index) => day(date, index));
}

/* ------------------------------------------------------- what is in there -- */

/**
 * The figures the acceptance run holds the read tools to, counted off the
 * calendar rather than reduced out of {@link month}. A tool that quietly changed
 * what it means by "planned" would have to change these by hand to stay green.
 */
export const TRUTH = {
  days: 31,
  sessionsPlanned: 18,
  sessionsDone: 15,
  sessionsMissed: 3,
  restDaysPlanned: 13,
  workouts: 15,
  workoutMinutes: 15 * 50,
  workoutActiveEnergyKcal: 15 * 400,
  loadAu: 15 * 100,
  /** 18 training days at 160 g, 13 rest days at 130 g, over 31 days. */
  averageProteinG: 147.4,
  averageKcal: 2100,
  daysMeetingProteinFloor: 18,
  /** The 7-day average moves 0.05 kg a day for 30 days. */
  weightAvg7FirstKg: 75,
  weightAvg7LastKg: 73.5,
  changeKg: -1.5,
  rateKgPerWeek: -0.35,
  /** 18 days at 80 and 13 at 70, rounded to a whole score. */
  averageReadiness: 76,
  trainAsPlannedDays: 18,
  capIntensityDays: 13,
  /** 18 days at energy 4, 13 at energy 3. */
  averageEnergy: 3.6,
  soreQuadDays: 4,
  /** Rest days plus the sessions that were done. */
  sessionWins: 28,
  proteinWins: 18,
  stepWins: 18,
  /** Every fourth night falls short of 450 minutes: 8 of 31. */
  sleepWins: 23,
  squatSets: 4,
  bestSquatKg: 27.5,
  bestSquatDate: "2026-10-27",
} as const;
