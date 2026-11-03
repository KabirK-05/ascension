import { testEnv } from "./env";
import { beforeAll, describe, expect, it } from "vitest";
import { readTools } from "../src/mcp/tools";
import { DOCUMENTED_EXAMPLE, LAST_DAY, TARGETS, makeRollup } from "./fixtures";
import { call, seedRollups } from "./helpers";

describe("the Tier-3 read tools", () => {
  beforeAll(async () => {
    await seedRollups();
  });

  it("registers exactly the eight tools docs/MUSE_CAPABILITIES.md lists", () => {
    expect(readTools.map((tool) => tool.name)).toEqual([
      "get_today",
      "get_workouts",
      "get_nutrition",
      "get_weight_trend",
      "get_readiness",
      "get_checkins",
      "get_exercise_history",
      "get_consistency_grid",
    ]);
  });

  it("names and describes every tool, and declares each one read-only", () => {
    for (const tool of readTools) {
      expect(tool.title.length, tool.name).toBeGreaterThan(0);
      expect(tool.description.length, tool.name).toBeGreaterThan(40);
      expect(tool.name).not.toMatch(/^(set|log|update|delete|accept|schedule|trigger)_/);
    }
  });

  describe("get_today", () => {
    it("returns the latest synced day and the seeded targets", async () => {
      const result = await call("get_today");
      expect(result.date).toBe(LAST_DAY);
      expect(result.asOf).toBe(LAST_DAY);
      expect(result.isLatestSynced).toBe(true);
      expect(result.rollup).toEqual(DOCUMENTED_EXAMPLE);
      expect(result.targets).toMatchObject({
        kcal: TARGETS.kcal,
        proteinMinG: TARGETS.proteinMinG,
        steps: TARGETS.steps,
        sleepMinutes: TARGETS.sleepMinutes,
        fatMinG: 60,
      });
    });

    it("reads an explicit earlier day and says it is not the latest", async () => {
      const result = await call("get_today", { date: "2026-10-05" });
      expect(result.date).toBe("2026-10-05");
      expect(result.isLatestSynced).toBe(false);
      expect(result.rollup.date).toBe("2026-10-05");
    });

    it("returns a null rollup for a day that has not synced", async () => {
      const result = await call("get_today", { date: "2020-01-01" });
      expect(result.rollup).toBeNull();
      expect(result.asOf).toBe(LAST_DAY);
    });
  });

  describe("get_workouts", () => {
    it("returns workouts newest first with zone minutes and adherence", async () => {
      const result = await call("get_workouts", { days: 30 });
      expect(result.asOf).toBe(LAST_DAY);
      expect(result.workouts.length).toBeGreaterThan(5);
      expect(result.workouts[0].date).toBe(LAST_DAY);
      expect(result.workouts[0].timeInZonesMinutes).toEqual({
        z1: 4,
        z2: 22,
        z3: 18,
        z4: 6,
        z5: 1,
      });
      const dates = result.workouts.map((w: { date: string }) => w.date);
      expect([...dates].sort().reverse()).toEqual(dates);

      expect(result.adherence.sessionsPlanned).toBe(
        result.adherence.sessionsDone + result.adherence.sessionsMissed,
      );
      expect(result.adherence.sessionsMissed).toBeGreaterThan(0);
      expect(result.totals.minutes).toBeGreaterThan(0);
      expect(result.totals.loadAu).toBeGreaterThan(0);
    });

    it("honours limit", async () => {
      const result = await call("get_workouts", { days: 90, limit: 3 });
      expect(result.workouts).toHaveLength(3);
      expect(result.count).toBe(3);
    });

    it("counts planned rest days separately from missed sessions", async () => {
      // A whole week: Monday to Friday train, Wednesday, Saturday and Sunday rest.
      const result = await call("get_workouts", { from: "2026-10-26", to: "2026-11-01" });
      expect(result.adherence.restDaysPlanned).toBe(3);
      expect(result.adherence.sessionsPlanned).toBe(4);
    });
  });

  describe("get_nutrition", () => {
    it("returns daily totals, averages and protein adherence", async () => {
      const result = await call("get_nutrition", { days: 14 });
      expect(result.days).toHaveLength(14);
      expect(result.days.at(-1)).toMatchObject({
        date: LAST_DAY,
        kcal: 2180,
        proteinG: 148,
        fatG: 64,
        carbsG: 248,
        waterMl: 2400,
        proteinWin: true,
      });
      expect(result.averages.kcal).toBeGreaterThan(1500);
      expect(result.targets.proteinMinG).toBe(140);
      expect(result.adherence.daysMeetingProteinFloor).toBe(
        result.days.filter((day: { proteinWin: boolean }) => day.proteinWin).length,
      );
    });

    it("averages over measured days only, ignoring nulls", async () => {
      const unmeasured = makeRollup("2026-11-04", 500);
      unmeasured.nutrition = {
        kcal: null,
        proteinG: null,
        fatG: null,
        carbsG: null,
        waterMl: null,
      };
      await testEnv.DB.prepare(
        `INSERT OR REPLACE INTO rollups (date, timezone, updatedAt, json, ingestedAt)
         VALUES (?1, ?2, ?3, ?4, ?5)`,
      )
        .bind(
          unmeasured.date,
          unmeasured.timezone,
          unmeasured.updatedAt,
          JSON.stringify(unmeasured),
          "2026-11-05T02:00:00Z",
        )
        .run();

      const result = await call("get_nutrition", { from: "2026-11-03", to: "2026-11-04" });
      expect(result.days).toHaveLength(2);
      expect(result.adherence.daysLogged).toBe(1);
      // The documented day's 2180 kcal, not an average dragged toward zero.
      expect(result.averages.kcal).toBe(2180);

      await testEnv.DB.prepare(`DELETE FROM rollups WHERE date = '2026-11-04'`).run();
    });
  });

  describe("get_weight_trend", () => {
    it("returns points, the stored 7-day average and kg per week", async () => {
      const result = await call("get_weight_trend", { days: 90 });
      expect(result.points.length).toBeGreaterThan(80);
      expect(result.latest).toMatchObject({
        date: LAST_DAY,
        weightKg: 73.6,
        avg7Kg: 73.9,
        rateKgPerWeek: -0.4,
      });
      expect(result.rateKgPerWeek).toBe(-0.4);
      // A cut, so the smoothed line falls across the window.
      expect(result.changeKg).toBeLessThan(0);
      expect(result.goalWeightKg).toBe(68);
      expect(result.toGoalKg).toBeCloseTo(5.9, 5);
    });

    it("skips days with no weigh-in", async () => {
      const noWeight = makeRollup("2026-11-05", 501);
      noWeight.body = {
        weightKg: null,
        weightAvg7Kg: null,
        rateKgPerWeek: null,
        bodyFatPct: null,
        waistCm: null,
      };
      await testEnv.DB.prepare(
        `INSERT OR REPLACE INTO rollups (date, timezone, updatedAt, json, ingestedAt)
         VALUES (?1, ?2, ?3, ?4, ?5)`,
      )
        .bind(
          noWeight.date,
          noWeight.timezone,
          noWeight.updatedAt,
          JSON.stringify(noWeight),
          "2026-11-06T02:00:00Z",
        )
        .run();

      const result = await call("get_weight_trend", { from: "2026-11-03", to: "2026-11-05" });
      expect(result.points.map((p: { date: string }) => p.date)).toEqual([LAST_DAY]);

      await testEnv.DB.prepare(`DELETE FROM rollups WHERE date = '2026-11-05'`).run();
    });
  });

  describe("get_readiness", () => {
    it("returns scores, verdicts and reasons with a verdict breakdown", async () => {
      const result = await call("get_readiness", { days: 14 });
      expect(result.latest).toMatchObject({
        date: LAST_DAY,
        score: 82,
        verdict: "trainAsPlanned",
        reasons: ["slept 7h42", "HRV near baseline"],
      });
      expect(Object.keys(result.verdictCounts).sort()).toEqual([
        "activeRecovery",
        "capIntensity",
        "swapSession",
        "trainAsPlanned",
      ]);
      const counted = Object.values(result.verdictCounts).reduce(
        (total: number, n) => total + (n as number),
        0,
      );
      expect(counted).toBe(result.count);
      expect(result.average).toBeGreaterThan(0);
    });

    it("omits days that have no readiness score", async () => {
      const result = await call("get_readiness", { days: 126 });
      expect(result.count).toBeLessThan(126);
    });
  });

  describe("get_checkins", () => {
    it("returns energy and soreness, and counts soreness per group", async () => {
      const result = await call("get_checkins", { days: 14 });
      expect(result.latest).toMatchObject({
        date: LAST_DAY,
        energy: 4,
        soreness: { quads: "sore", back: "mild", core: "none" },
      });
      expect(Object.keys(result.sorenessByGroup).sort()).toEqual([
        "arms",
        "back",
        "chest",
        "core",
        "glutes",
        "hamstrings",
        "quads",
        "shoulders",
      ]);
      for (const group of Object.values(result.sorenessByGroup)) {
        const levels = group as { none: number; mild: number; sore: number };
        expect(levels.none + levels.mild + levels.sore).toBe(result.count);
      }
      expect(result.averageEnergy).toBeGreaterThanOrEqual(1);
      expect(result.averageEnergy).toBeLessThanOrEqual(5);
    });
  });

  describe("get_exercise_history", () => {
    it("lists the exercises in the window when no id is given", async () => {
      const result = await call("get_exercise_history", { days: 180 });
      expect(result.exerciseId).toBeNull();
      const ids = result.exercises.map((e: { exerciseId: string }) => e.exerciseId);
      expect(ids).toContain("DB_Bench_Press");
      expect(ids).toContain("Goblet_Squat");
      expect(result.exercises[0].lastDate).toBe(LAST_DAY);
    });

    it("returns one exercise's sets newest first, with the best set", async () => {
      const result = await call("get_exercise_history", {
        exerciseId: "DB_Bench_Press",
        days: 180,
      });
      expect(result.sets.length).toBeGreaterThan(3);
      expect(result.sets[0].date).toBe(LAST_DAY);
      expect(result.latest).toMatchObject({ date: LAST_DAY, weightKg: 20, reps: 11 });
      for (const set of result.sets) {
        expect(set.weightKg).toBeLessThanOrEqual(result.best.weightKg);
      }
    });

    it("offers the ids it does know when the id matches nothing", async () => {
      const result = await call("get_exercise_history", {
        exerciseId: "Barbell_Snatch",
        days: 180,
      });
      expect(result.sets).toEqual([]);
      expect(result.best).toBeNull();
      expect(result.knownExerciseIds).toContain("Goblet_Squat");
    });
  });

  describe("get_consistency_grid", () => {
    it("returns 17 Monday-to-Sunday weeks of wins", async () => {
      const result = await call("get_consistency_grid");
      expect(result.weeks).toBe(17);
      expect(result.grid).toHaveLength(17);
      expect(result.grid.flatMap((week: { days: unknown[] }) => week.days)).toHaveLength(
        119,
      );

      // Anchored on the week containing the latest synced day.
      expect(result.grid.at(-1).weekStart).toBe("2026-11-02");
      expect(result.from).toBe("2026-07-13");
      expect(result.to).toBe("2026-11-08");
      for (const week of result.grid) {
        expect(week.days).toHaveLength(7);
      }
    });

    it("carries the four wins the device computed, untouched", async () => {
      const result = await call("get_consistency_grid");
      const lastWeek = result.grid.at(-1);
      // Monday 2026-11-02 then Tuesday 2026-11-03, the documented example.
      expect(lastWeek.days[1]).toEqual({
        date: LAST_DAY,
        wins: { session: true, protein: true, steps: true, sleep: true, total: 4 },
      });
      expect(result.totals.perfectDays).toBeGreaterThan(0);
      expect(result.totals.session).toBeLessThanOrEqual(result.totals.daysSynced);
      expect(result.totals.averageWins).toBeGreaterThan(0);
    });

    it("leaves a day with no rollup null rather than calling it a loss", async () => {
      const result = await call("get_consistency_grid");
      const lastWeek = result.grid.at(-1);
      // Fixtures stop at Tuesday, so Wednesday onward has never synced.
      expect(lastWeek.days.slice(2)).toEqual([null, null, null, null, null]);
    });

    it("takes a shorter window", async () => {
      const result = await call("get_consistency_grid", { weeks: 4 });
      expect(result.grid).toHaveLength(4);
      expect(result.from).toBe("2026-10-12");
    });
  });

  describe("an empty database", () => {
    it("reports nothing synced rather than guessing a window", async () => {
      await testEnv.DB.prepare(`DELETE FROM rollups`).run();
      for (const tool of readTools) {
        const result = await call(tool.name);
        expect(result.asOf, tool.name).toBeNull();
      }
      await seedRollups();
    });
  });

  it("rejects a reversed window", async () => {
    await expect(
      call("get_nutrition", { from: "2026-11-03", to: "2026-10-01" }),
    ).rejects.toThrow(/after/);
  });
});
