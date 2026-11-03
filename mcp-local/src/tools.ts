/**
 * Tier 3 — the eight read tools, over the export folder.
 *
 * Everything from `ReadTool` down is `edge/src/mcp/tools.ts` verbatim. That is the
 * point of the ticket: a divergence here would have Muse and Claude Code describe the
 * same training week differently. Only the imports above and `ToolContext` below
 * change, and `test/parity.test.ts` diffs this file against the cloud server's to
 * prove nothing else has.
 *
 * Scope is daily rollups, by the owner's choice: no raw HR series, no per-meal rows,
 * no sleep stages. There are no write tools here, and on this transport there never
 * will be — the folder is opened read-only.
 */
import { z } from "zod";
import {
  isoDate,
  muscleGroups,
  sorenessLevels,
  verdicts,
  type DayRollup,
  type MuscleGroup,
} from "./contract";
import { addDays, enumerateDates, isoWeekStart } from "./dates";
import type { ExportFolder } from "./export-folder";
import { readGoalSettings } from "./store/documents";
import { getRollup, latestDate } from "./store/rollups";
import { mean, rangeArgs, resolveRange, round, sum, type RangeArgs } from "./range";

/**
 * `db` keeps the name the cloud server's tool bodies use, so those bodies need no
 * edit. Here it is the export folder, which answers the same four questions D1 does.
 */
export type ToolContext = { db: ExportFolder };

export type ReadTool = {
  name: string;
  title: string;
  description: string;
  inputSchema: z.ZodObject<z.ZodRawShape>;
  run(args: never, ctx: ToolContext): Promise<Record<string, unknown>>;
};

function defineTool<Shape extends z.ZodRawShape>(tool: {
  name: string;
  title: string;
  description: string;
  inputSchema: z.ZodObject<Shape>;
  run(args: z.infer<z.ZodObject<Shape>>, ctx: ToolContext): Promise<Record<string, unknown>>;
}): ReadTool {
  return tool as unknown as ReadTool;
}

/** The shape every windowed tool reports when nothing has ever been synced. */
const nothingSynced = { asOf: null, from: null, to: null };

function withWindow(
  range: { from: string; to: string; asOf: string; unreadableDates: string[] },
  body: Record<string, unknown>,
): Record<string, unknown> {
  return {
    from: range.from,
    to: range.to,
    asOf: range.asOf,
    ...(range.unreadableDates.length > 0
      ? { unreadableDates: range.unreadableDates }
      : {}),
    ...body,
  };
}

/* ------------------------------------------------------------- get_today -- */

const getToday = defineTool({
  name: "get_today",
  title: "Today",
  description:
    "The full daily rollup for one day — nutrition, activity, sleep, vitals, body, training, check-in, readiness and the four consistency wins — plus the current calorie and macro targets to judge it against. Defaults to the most recently synced day. Data is as fresh as the last phone sync, not live.",
  inputSchema: z.object({
    date: isoDate
      .optional()
      .describe("Day to read, YYYY-MM-DD. Defaults to the most recent synced day."),
  }),
  async run(args, { db }) {
    const asOf = await latestDate(db);
    const date = args.date ?? asOf;
    if (!date) return { date: null, asOf: null, rollup: null, targets: null };

    const [rollup, goalSettings] = await Promise.all([
      getRollup(db, date),
      readGoalSettings(db),
    ]);
    return {
      date,
      asOf,
      isLatestSynced: date === asOf,
      rollup,
      targets: goalSettings?.targets ?? null,
    };
  },
});

/* ---------------------------------------------------------- get_workouts -- */

const getWorkouts = defineTool({
  name: "get_workouts",
  title: "Workouts",
  description:
    "Workouts the Apple Watch recorded, newest first, with duration, active energy, average and max heart rate, and minutes in each heart-rate zone. Also reports planned-versus-done adherence and total training load for the window. Defaults to the last 30 days.",
  inputSchema: z.object({
    ...rangeArgs,
    limit: z
      .number()
      .int()
      .min(1)
      .max(200)
      .optional()
      .describe("Most recent workouts to return. Defaults to 50."),
  }),
  async run(args, { db }) {
    const range = await resolveRange(db, args, 30);
    if (!range) return { ...nothingSynced, workouts: [], adherence: null, totals: null };

    const limit = args.limit ?? 50;
    const workouts = range.rollups
      .flatMap((day) =>
        day.training.workouts.map((workout) => ({
          date: day.date,
          sessionPlanned: day.training.sessionPlanned,
          loadAu: day.training.loadAu,
          ...workout,
        })),
      )
      .sort((a, b) => (a.startedAt < b.startedAt ? 1 : -1))
      .slice(0, limit);

    const planned = range.rollups.filter(
      (day) => day.training.sessionPlanned !== null && day.training.sessionPlanned !== "rest",
    );
    const restDays = range.rollups.filter(
      (day) => day.training.sessionPlanned === "rest",
    );

    return withWindow(range, {
      count: workouts.length,
      workouts,
      adherence: {
        daysSynced: range.rollups.length,
        sessionsPlanned: planned.length,
        sessionsDone: planned.filter((day) => day.training.sessionDone).length,
        sessionsMissed: planned.filter((day) => !day.training.sessionDone).length,
        restDaysPlanned: restDays.length,
      },
      totals: {
        workouts: range.rollups.reduce(
          (total, day) => total + day.training.workouts.length,
          0,
        ),
        minutes: round(
          sum(
            range.rollups.flatMap((day) =>
              day.training.workouts.map((workout) => workout.durationMinutes),
            ),
          ),
        ),
        activeEnergyKcal: round(
          sum(
            range.rollups.flatMap((day) =>
              day.training.workouts.map((workout) => workout.activeEnergyKcal),
            ),
          ),
        ),
        loadAu: round(sum(range.rollups.map((day) => day.training.loadAu))),
      },
    });
  },
});

/* --------------------------------------------------------- get_nutrition -- */

const getNutrition = defineTool({
  name: "get_nutrition",
  title: "Nutrition",
  description:
    "Daily nutrition totals — calories, protein, fat, carbohydrate and water — with window averages and how many days cleared the protein floor. Totals only: per-meal rows never leave the device. Defaults to the last 14 days.",
  inputSchema: z.object(rangeArgs),
  async run(args, { db }) {
    const range = await resolveRange(db, args, 14);
    if (!range) return { ...nothingSynced, days: [], averages: null, targets: null };

    const goalSettings = await readGoalSettings(db);
    const days = range.rollups.map((day) => ({
      date: day.date,
      ...day.nutrition,
      proteinWin: day.wins.protein,
    }));
    const logged = days.filter((day) => day.kcal !== null || day.proteinG !== null);

    return withWindow(range, {
      days,
      averages: {
        kcal: round(mean(days.map((day) => day.kcal)), 0),
        proteinG: round(mean(days.map((day) => day.proteinG))),
        fatG: round(mean(days.map((day) => day.fatG))),
        carbsG: round(mean(days.map((day) => day.carbsG))),
        waterMl: round(mean(days.map((day) => day.waterMl)), 0),
      },
      targets: goalSettings?.targets ?? null,
      adherence: {
        daysSynced: days.length,
        daysLogged: logged.length,
        daysMeetingProteinFloor: days.filter((day) => day.proteinWin).length,
      },
    });
  },
});

/* ------------------------------------------------------ get_weight_trend -- */

const getWeightTrend = defineTool({
  name: "get_weight_trend",
  title: "Weight trend",
  description:
    "Weight over time in kg: each weigh-in, its 7-day average, and the rate of change in kg per week. The average and the rate are the ones the device computed and stored, so they always agree with what the app shows. Defaults to the last 90 days.",
  inputSchema: z.object(rangeArgs),
  async run(args, { db }) {
    const range = await resolveRange(db, args, 90);
    if (!range) return { ...nothingSynced, points: [], latest: null };

    const goalSettings = await readGoalSettings(db);
    const points = range.rollups
      .filter((day) => day.body.weightKg !== null || day.body.weightAvg7Kg !== null)
      .map((day) => ({
        date: day.date,
        weightKg: day.body.weightKg,
        avg7Kg: day.body.weightAvg7Kg,
        rateKgPerWeek: day.body.rateKgPerWeek,
      }));

    const smoothed = points.filter(
      (point): point is typeof point & { avg7Kg: number } => point.avg7Kg !== null,
    );
    const first = smoothed[0] ?? null;
    const last = smoothed[smoothed.length - 1] ?? null;
    const latest = points[points.length - 1] ?? null;
    const goalWeightKg = goalSettings?.body.goalWeightKg ?? null;

    return withWindow(range, {
      count: points.length,
      points,
      latest,
      /** Movement of the 7-day average across the window, not a re-derived rate. */
      changeKg:
        first && last ? round(last.avg7Kg - first.avg7Kg, 2) : null,
      rateKgPerWeek: latest?.rateKgPerWeek ?? null,
      goalWeightKg,
      toGoalKg:
        goalWeightKg !== null && latest?.avg7Kg !== null && latest?.avg7Kg !== undefined
          ? round(latest.avg7Kg - goalWeightKg, 2)
          : null,
    });
  },
});

/* --------------------------------------------------------- get_readiness -- */

const getReadiness = defineTool({
  name: "get_readiness",
  title: "Readiness",
  description:
    "Daily readiness score (0–100), its verdict — trainAsPlanned, capIntensity, swapSession or activeRecovery — and the reasons the engine gave. Includes the window average and how often each verdict came up. Defaults to the last 14 days.",
  inputSchema: z.object(rangeArgs),
  async run(args, { db }) {
    const range = await resolveRange(db, args, 14);
    if (!range) return { ...nothingSynced, days: [], average: null, latest: null };

    const days = range.rollups
      .filter((day) => day.readiness !== null)
      .map((day) => ({ date: day.date, ...day.readiness! }));

    const verdictCounts = Object.fromEntries(
      verdicts.map((verdict) => [
        verdict,
        days.filter((day) => day.verdict === verdict).length,
      ]),
    );

    return withWindow(range, {
      count: days.length,
      days,
      average: round(mean(days.map((day) => day.score)), 0),
      verdictCounts,
      latest: days[days.length - 1] ?? null,
    });
  },
});

/* ---------------------------------------------------------- get_checkins -- */

const getCheckins = defineTool({
  name: "get_checkins",
  title: "Check-ins",
  description:
    "Morning check-ins: energy 1–5 and soreness per muscle group (none, mild or sore). Includes average energy and, per group, how many days came back mild or sore — which is what tells you whether a session needs swapping. Defaults to the last 14 days.",
  inputSchema: z.object(rangeArgs),
  async run(args, { db }) {
    const range = await resolveRange(db, args, 14);
    if (!range) return { ...nothingSynced, days: [], averageEnergy: null };

    const days = range.rollups
      .filter((day) => day.checkIn !== null)
      .map((day) => ({ date: day.date, ...day.checkIn! }));

    const sorenessByGroup = Object.fromEntries(
      muscleGroups.map((group: MuscleGroup) => [
        group,
        Object.fromEntries(
          sorenessLevels.map((level) => [
            level,
            days.filter((day) => day.soreness[group] === level).length,
          ]),
        ),
      ]),
    );

    return withWindow(range, {
      count: days.length,
      days,
      averageEnergy: round(mean(days.map((day) => day.energy))),
      sorenessByGroup,
      latest: days[days.length - 1] ?? null,
    });
  },
});

/* -------------------------------------------------- get_exercise_history -- */

function betterSet(
  a: { weightKg: number; reps: number },
  b: { weightKg: number; reps: number },
): boolean {
  return a.weightKg > b.weightKg || (a.weightKg === b.weightKg && a.reps > b.reps);
}

const getExerciseHistory = defineTool({
  name: "get_exercise_history",
  title: "Exercise history",
  description:
    "Logged top sets for one exercise over time — weight in kg and reps per day — with the best set in the window. Omit `exerciseId` to list every exercise that has a logged set in the window, with its last date and best weight. Defaults to the last 180 days.",
  inputSchema: z.object({
    exerciseId: z
      .string()
      .min(1)
      .optional()
      .describe(
        "A free-exercise-db id, e.g. `Goblet_Squat`. Omit to list the available ids.",
      ),
    ...rangeArgs,
    limit: z
      .number()
      .int()
      .min(1)
      .max(500)
      .optional()
      .describe("Most recent sets to return. Defaults to 100."),
  }),
  async run(args, { db }) {
    const range = await resolveRange(db, args, 180);
    if (!range) return { ...nothingSynced, exerciseId: args.exerciseId ?? null, sets: [] };

    const all = range.rollups.flatMap((day) =>
      day.training.topSets.map((set) => ({ date: day.date, ...set })),
    );

    if (!args.exerciseId) {
      const byId = new Map<string, { sets: number; lastDate: string; bestWeightKg: number }>();
      for (const set of all) {
        const seen = byId.get(set.exerciseId);
        byId.set(set.exerciseId, {
          sets: (seen?.sets ?? 0) + 1,
          lastDate:
            seen && seen.lastDate > set.date ? seen.lastDate : set.date,
          bestWeightKg: Math.max(seen?.bestWeightKg ?? -Infinity, set.weightKg),
        });
      }
      return withWindow(range, {
        exerciseId: null,
        exercises: [...byId.entries()]
          .map(([exerciseId, summary]) => ({ exerciseId, ...summary }))
          .sort((a, b) => (a.lastDate < b.lastDate ? 1 : -1)),
      });
    }

    const sets = all
      .filter((set) => set.exerciseId === args.exerciseId)
      .sort((a, b) => (a.date < b.date ? 1 : -1))
      .slice(0, args.limit ?? 100);

    let best: (typeof sets)[number] | null = null;
    for (const set of sets) if (!best || betterSet(set, best)) best = set;

    return withWindow(range, {
      exerciseId: args.exerciseId,
      count: sets.length,
      sets,
      best,
      latest: sets[0] ?? null,
      ...(sets.length === 0
        ? {
            knownExerciseIds: [...new Set(all.map((set) => set.exerciseId))].sort(),
          }
        : {}),
    });
  },
});

/* -------------------------------------------------- get_consistency_grid -- */

/** 7 rows by 17 columns is what the iOS Today grid renders. */
const GRID_WEEKS = 17;

const getConsistencyGrid = defineTool({
  name: "get_consistency_grid",
  title: "Consistency grid",
  description:
    "The consistency grid: the four daily wins — session, protein, steps, sleep — for the trailing 17 full weeks, as the Today screen draws them. Weeks run Monday to Sunday; a day with no synced rollup is null, not a loss. The wins are computed on the device and stored, so this can never disagree with the app.",
  inputSchema: z.object({
    to: isoDate
      .optional()
      .describe("Last day to include. Defaults to the most recent synced day."),
    weeks: z
      .number()
      .int()
      .min(1)
      .max(52)
      .optional()
      .describe(`Trailing full weeks to return. Defaults to ${GRID_WEEKS}.`),
  }),
  async run(args, { db }) {
    const weeks = args.weeks ?? GRID_WEEKS;
    const asOf = await latestDate(db);
    const anchor = args.to ?? asOf;
    if (!anchor || !asOf) {
      return { ...nothingSynced, weeks, grid: [], totals: null };
    }

    const lastWeekStart = isoWeekStart(anchor);
    const from = addDays(lastWeekStart, -(weeks - 1) * 7);
    const to = addDays(lastWeekStart, 6);

    const range = await resolveRange(db, { from, to }, weeks * 7);
    if (!range) return { ...nothingSynced, weeks, grid: [], totals: null };

    const byDate = new Map<string, DayRollup>(
      range.rollups.map((day) => [day.date, day]),
    );
    const grid = Array.from({ length: weeks }, (_, week) => {
      const weekStart = addDays(from, week * 7);
      return {
        weekStart,
        days: enumerateDates(weekStart, addDays(weekStart, 6)).map((date) => {
          const day = byDate.get(date);
          return day ? { date, wins: day.wins } : null;
        }),
      };
    });

    const present = range.rollups;
    return {
      from,
      to,
      asOf,
      weeks,
      ...(range.unreadableDates.length > 0
        ? { unreadableDates: range.unreadableDates }
        : {}),
      grid,
      totals: {
        daysSynced: present.length,
        session: present.filter((day) => day.wins.session).length,
        protein: present.filter((day) => day.wins.protein).length,
        steps: present.filter((day) => day.wins.steps).length,
        sleep: present.filter((day) => day.wins.sleep).length,
        perfectDays: present.filter((day) => day.wins.total === 4).length,
        averageWins: round(mean(present.map((day) => day.wins.total)), 2),
      },
    };
  },
});

export const readTools: ReadTool[] = [
  getToday,
  getWorkouts,
  getNutrition,
  getWeightTrend,
  getReadiness,
  getCheckins,
  getExerciseHistory,
  getConsistencyGrid,
];

export type { RangeArgs };
