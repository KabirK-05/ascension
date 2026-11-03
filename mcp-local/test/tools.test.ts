/**
 * The eight read tools over fixture export folders.
 *
 * The strongest assertions here are the ones that check a tool against
 * `summary-latest.md` in the same folder: the app rendered that file from the same
 * rollups, so if this server's adherence or averages disagree with it, this server is
 * reading the export wrong.
 */
import { rm } from "node:fs/promises";
import { afterEach, describe, expect, it } from "vitest";
import { ExportFolderUnavailable } from "../src/export-folder";
import {
  emptyFolderDir,
  fixtureDir,
  fixtureFolder,
  folderAt,
  folderDigest,
} from "./support/folders";
import { runTool, toolNames } from "./support/tools";

const temporary: string[] = [];
afterEach(async () => {
  while (temporary.length > 0) {
    await rm(temporary.pop()!, { recursive: true, force: true });
  }
});

/** Arguments that exercise each tool's real work rather than only its defaults. */
const windowed: Record<string, Record<string, unknown>> = {
  get_today: {},
  get_workouts: { days: 28 },
  get_nutrition: { days: 28 },
  get_weight_trend: { days: 28 },
  get_readiness: { days: 28 },
  get_checkins: { days: 28 },
  get_exercise_history: { days: 28 },
  get_consistency_grid: { weeks: 4 },
};

describe("every tool, against a full folder", () => {
  it.each(toolNames)("%s answers with the export's own asOf", async (name) => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool(name, windowed[name]!, folder);
    expect(payload.asOf).toBe("2026-11-30");
  });

  it("get_today returns the latest day and the targets to judge it against", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_today", {}, folder);

    expect(payload.date).toBe("2026-11-30");
    expect(payload.isLatestSynced).toBe(true);
    expect(payload.rollup.nutrition.kcal).toBe(2_281);
    expect(payload.rollup.training.sessionPlanned).toBe("upperA");
    expect(payload.targets.kcal).toBe(2_200);
    expect(payload.targets.proteinMinG).toBe(140);
  });

  it("get_today reads an older day when asked", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_today", { date: "2026-11-03" }, folder);

    expect(payload.date).toBe("2026-11-03");
    expect(payload.isLatestSynced).toBe(false);
    expect(payload.rollup.readiness.verdict).toBe("swapSession");
  });

  it("get_today reports a day the export does not hold as null, not empty", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_today", { date: "2026-10-01" }, folder);

    expect(payload.date).toBe("2026-10-01");
    expect(payload.rollup).toBeNull();
    expect(payload.asOf).toBe("2026-11-30");
  });

  it("get_workouts agrees with the adherence summary-latest.md prints", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_workouts", { days: 28 }, folder);

    // summary-latest.md: "Sessions: 13 of 16 planned (81%)".
    expect(payload.adherence).toEqual({
      daysSynced: 28,
      sessionsPlanned: 16,
      sessionsDone: 13,
      sessionsMissed: 3,
      restDaysPlanned: 12,
    });
    expect(payload.totals.workouts).toBe(13);
    expect(payload.workouts[0].date).toBe("2026-11-30");
    expect(payload.workouts[0].timeInZonesMinutes.z2).toBe(22);
  });

  it("get_workouts returns newest first and honours the limit", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_workouts", { days: 28, limit: 3 }, folder);

    expect(payload.workouts).toHaveLength(3);
    expect(payload.workouts.map((w: { date: string }) => w.date)).toEqual([
      "2026-11-30",
      "2026-11-27",
      "2026-11-26",
    ]);
  });

  it("get_nutrition agrees with the averages summary-latest.md prints", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_nutrition", { days: 28 }, folder);

    // summary-latest.md 28-day column: 2,186 kcal, 147 g protein.
    expect(payload.averages.kcal).toBe(2_186);
    expect(Math.round(payload.averages.proteinG)).toBe(147);
    // "Protein ≥ 140 g: 19 of 28 (68%)".
    expect(payload.adherence).toEqual({
      daysSynced: 28,
      daysLogged: 27,
      daysMeetingProteinFloor: 19,
    });
  });

  it("get_weight_trend agrees with the trend line summary-latest.md prints", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_weight_trend", { days: 28 }, folder);

    // "Trend: 73.6 kg · 7-day avg 73.7 kg · −0.4 kg/week · goal 68.0 kg".
    expect(payload.latest).toEqual({
      date: "2026-11-30",
      weightKg: 73.6,
      avg7Kg: 73.7,
      rateKgPerWeek: -0.4,
    });
    expect(payload.rateKgPerWeek).toBe(-0.4);
    expect(payload.goalWeightKg).toBe(68);
    expect(payload.toGoalKg).toBe(5.7);
    expect(payload.changeKg).toBe(-0.8);
  });

  it("get_readiness counts every verdict, including the ones that never came up", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_readiness", { days: 28 }, folder);

    expect(payload.count).toBe(27);
    expect(payload.average).toBe(81);
    expect(payload.verdictCounts).toEqual({
      trainAsPlanned: 15,
      capIntensity: 9,
      swapSession: 3,
      activeRecovery: 0,
    });
    expect(payload.latest.date).toBe("2026-11-30");
    expect(payload.latest.reasons.length).toBeGreaterThan(0);
  });

  it("get_checkins reports soreness per group, every level", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_checkins", { days: 28 }, folder);

    expect(payload.count).toBe(21);
    expect(payload.averageEnergy).toBe(3.9);
    expect(payload.sorenessByGroup.back).toEqual({ none: 8, mild: 7, sore: 6 });
    expect(Object.keys(payload.sorenessByGroup)).toHaveLength(8);
  });

  it("get_exercise_history lists the exercises, then one exercise's sets", async () => {
    const { folder } = fixtureFolder("full");
    const listed = await runTool("get_exercise_history", { days: 28 }, folder);
    expect(listed.exerciseId).toBeNull();
    expect(listed.exercises.map((e: { exerciseId: string }) => e.exerciseId)).toContain(
      "Goblet_Squat",
    );

    const one = await runTool(
      "get_exercise_history",
      { exerciseId: "Goblet_Squat", days: 28 },
      folder,
    );
    expect(one.count).toBe(8);
    expect(one.best).toEqual({
      date: "2026-11-27",
      exerciseId: "Goblet_Squat",
      weightKg: 31.5,
      reps: 12,
    });
  });

  it("get_exercise_history names the ids it does know when asked for one it does not", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool(
      "get_exercise_history",
      { exerciseId: "Barbell_Bench_Press", days: 28 },
      folder,
    );

    expect(payload.sets).toEqual([]);
    expect(payload.knownExerciseIds).toEqual([
      "DB_Bench_Press",
      "Goblet_Squat",
      "Lat_Pulldown",
      "Romanian_Deadlift",
    ]);
  });

  it("get_consistency_grid draws whole Monday weeks, with a null for a day never synced", async () => {
    const { folder } = fixtureFolder("full");
    const payload = await runTool("get_consistency_grid", { weeks: 4 }, folder);

    expect(payload.weeks).toBe(4);
    expect(payload.grid).toHaveLength(4);
    expect(payload.from).toBe("2026-11-09");
    expect(payload.to).toBe("2026-12-06");
    for (const week of payload.grid) expect(week.days).toHaveLength(7);

    // The window runs past the last synced day, and those days are null — not a loss.
    const lastWeek = payload.grid[3];
    expect(lastWeek.weekStart).toBe("2026-11-30");
    expect(lastWeek.days[0].date).toBe("2026-11-30");
    expect(lastWeek.days[1]).toBeNull();
    expect(payload.totals.daysSynced).toBe(22);
    expect(payload.totals.perfectDays).toBe(4);
  });

  it("rejects a window that runs backwards", async () => {
    const { folder } = fixtureFolder("full");
    await expect(
      runTool("get_nutrition", { from: "2026-11-20", to: "2026-11-10" }, folder),
    ).rejects.toThrow("is after");
  });
});

describe("every tool, against a folder with no export", () => {
  it.each(toolNames)("%s says nothing is synced instead of throwing", async (name) => {
    const dir = await emptyFolderDir();
    temporary.push(dir);
    const { folder } = folderAt(dir);
    const payload = await runTool(name, windowed[name]!, folder);

    expect(payload.asOf).toBeNull();
    // Nothing is invented around the Mac's clock: there is no window either.
    expect(payload.from ?? null).toBeNull();
    expect(payload.to ?? null).toBeNull();
  });

  it.each(toolNames)("%s says the same for a folder holding only markdown", async (name) => {
    const { folder } = fixtureFolder("missing-export");
    const payload = await runTool(name, windowed[name]!, folder);
    expect(payload.asOf).toBeNull();
  });

  it.each(toolNames)("%s says the same for a half-written export", async (name) => {
    const { folder } = fixtureFolder("partial");
    const payload = await runTool(name, windowed[name]!, folder);
    expect(payload.asOf).toBeNull();
  });
});

describe("every tool, against malformed rows", () => {
  it.each(toolNames)("%s anchors on the newest readable day", async (name) => {
    const { folder } = fixtureFolder("malformed");
    const payload = await runTool(name, windowed[name]!, folder);
    expect(payload.asOf).toBe("2026-11-06");
  });

  // `get_today` reads one day and so carries no window; the cloud server's
  // `unreadableDates` rides on the windowed tools, and this matches it.
  it.each(toolNames.filter((name) => name !== "get_today"))(
    "%s names the days it could not read",
    async (name) => {
      const { folder } = fixtureFolder("malformed");
      const payload = await runTool(name, windowed[name]!, folder);
      expect(payload.unreadableDates).toEqual(["2026-11-04", "2026-11-05"]);
    },
  );

  it("get_today reports an unreadable day as no day, never as an empty one", async () => {
    const { folder } = fixtureFolder("malformed");
    const payload = await runTool("get_today", { date: "2026-11-04" }, folder);

    expect(payload.rollup).toBeNull();
    expect(payload.asOf).toBe("2026-11-06");
  });

  it("does not let the broken day's calories count as zero", async () => {
    const { folder } = fixtureFolder("malformed");
    const payload = await runTool("get_nutrition", { days: 28 }, folder);

    // Two readable days, 2,050 and 2,209 kcal. A zero for either broken day would drag
    // the average to about 1,065.
    expect(payload.days.map((day: { date: string }) => day.date)).toEqual([
      "2026-11-03",
      "2026-11-06",
    ]);
    expect(payload.averages.kcal).toBe(2_130);
  });
});

describe("every tool, against a folder that is not there", () => {
  it.each(toolNames)("%s raises a configuration error", async (name) => {
    const { folder } = folderAt("/nowhere/ascension-does-not-exist");
    await expect(runTool(name, windowed[name]!, folder)).rejects.toThrow(
      ExportFolderUnavailable,
    );
  });
});

describe("read-only", () => {
  it("leaves the folder byte-identical after every tool has run", async () => {
    const dir = fixtureDir("full");
    const before = await folderDigest(dir);
    const { folder } = folderAt(dir);

    for (const name of toolNames) await runTool(name, windowed[name]!, folder);

    expect(await folderDigest(dir)).toBe(before);
  });
});
