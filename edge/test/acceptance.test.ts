/**
 * ASC-18 — the spec's own acceptance test (§9.3), extended for writes.
 *
 * "With *only* these tools connected, Muse answers 'how is my training going
 * this month?' accurately" — and, since ASC-13, also changes a calorie target,
 * swaps a session, and leaves a meal for the phone to write into Apple Health.
 *
 * What makes this different from every other suite in this directory:
 *
 *  - It goes in the front door. `Connector` registers a client, approves the
 *    consent page with the owner's password, exchanges a PKCE code for a bearer
 *    token, and speaks JSON-RPC over Streamable HTTP. No internal function is
 *    called; if OAuth, the route or the transport breaks, nothing below runs.
 *  - The data arrives the way the phone sends it, through `POST /v1/ingest`
 *    with the device token — so the seed is contract-valid by construction.
 *  - Every figure is checked against `TRUTH` in `acceptance-month.ts`, which is
 *    counted off the calendar by hand, and *also* against an independent
 *    reduction over the same rollups. A tool that re-derived a number wrongly
 *    would have to be wrong in the same way twice to stay green.
 *
 * The device half of the round trip — draining these mutations, writing the
 * meal into HealthKit — is in `app/Tests/AcceptanceTests.swift`. The two meet
 * at `test/golden/mutations.page.json`, which this file asserts the Worker
 * produces and that file replays. See the PR for why the harness is a pair and
 * not one process.
 */
import { SELF } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { Connector, ORIGIN } from "./connector";
import { MONTH_FROM, MONTH_TO, TRUTH, month } from "./acceptance-month";
import { GOAL_SETTINGS, PROGRAM } from "./fixtures";
import { documentRow, mutationRows, seedDocuments } from "./helpers";
import goldenPage from "./golden/mutations.page.json" with { type: "json" };

const DEVICE_TOKEN = "test-device-token";
const WINDOW = { from: MONTH_FROM, to: MONTH_TO };

/** The rollups, held once so the assertions can reduce over them independently. */
const DAYS = month();

const sum = (values: number[]) => values.reduce((total, value) => total + value, 0);
const mean = (values: number[]) => sum(values) / values.length;

let muse: Connector;

/* ------------------------------------------------------------------------- */

describe("ASC-18 — the acceptance run, with only the connector attached", () => {
  beforeAll(async () => {
    await seedDocuments({ program: PROGRAM });

    // Stream A: the phone pushes the month. Device token, not an OAuth grant.
    const ingest = await SELF.fetch(`${ORIGIN}/v1/ingest`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${DEVICE_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ rollups: DAYS }),
    });
    expect(ingest.status, await ingest.clone().text()).toBe(200);
    expect(await ingest.json()).toMatchObject({ accepted: TRUTH.days });

    muse = await Connector.connect();
  });

  /* ----------------------------------------------------- the connection -- */

  it("is a connector with a real token, and nothing less reaches /mcp", async () => {
    const { payload } = await muse.rpc("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "Muse", version: "1" },
    });
    expect(payload.result.serverInfo.name).toBe("ascension");

    const anonymous = await SELF.fetch(`${ORIGIN}/mcp`, {
      method: "POST",
      headers: { Host: "localhost:8787", "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
    });
    expect(anonymous.status).toBe(401);
  });

  it("offers the eight read tools and the eleven write tools, and nothing else", async () => {
    const { payload } = await muse.rpc("tools/list");
    const names = (payload.result.tools as Array<{ name: string }>).map((t) => t.name);
    expect(names).toHaveLength(19);
    expect(names.filter((name) => name.startsWith("get_"))).toHaveLength(8);
  });

  /* ------------------------------- 1. how is my training going this month -- */

  describe("1. how is my training going this month?", () => {
    it("reports sessions planned against sessions done, and they are the month's", async () => {
      const body = await muse.ok("get_workouts", { ...WINDOW, limit: 200 });

      expect(body.from).toBe(MONTH_FROM);
      expect(body.to).toBe(MONTH_TO);
      expect(body.asOf).toBe(MONTH_TO);

      expect(body.adherence).toEqual({
        daysSynced: TRUTH.days,
        sessionsPlanned: TRUTH.sessionsPlanned,
        sessionsDone: TRUTH.sessionsDone,
        sessionsMissed: TRUTH.sessionsMissed,
        restDaysPlanned: TRUTH.restDaysPlanned,
      });

      // The same four counts, reduced here rather than read off the calendar.
      const planned = DAYS.filter((day) => day.training.sessionPlanned !== "rest");
      expect(body.adherence.sessionsPlanned).toBe(planned.length);
      expect(body.adherence.sessionsDone).toBe(
        planned.filter((day) => day.training.sessionDone).length,
      );
      expect(body.adherence.restDaysPlanned).toBe(DAYS.length - planned.length);
    });

    it("totals the month's training, and every workout it returns is in the data", async () => {
      const body = await muse.ok("get_workouts", { ...WINDOW, limit: 200 });

      expect(body.totals).toEqual({
        workouts: TRUTH.workouts,
        minutes: TRUTH.workoutMinutes,
        activeEnergyKcal: TRUTH.workoutActiveEnergyKcal,
        loadAu: TRUTH.loadAu,
      });
      expect(body.count).toBe(TRUTH.workouts);

      const seeded = new Map(
        DAYS.flatMap((day) => day.training.workouts.map((w) => [w.healthKitId, w] as const)),
      );
      expect(seeded.size).toBe(TRUTH.workouts);
      for (const workout of body.workouts as Array<Record<string, any>>) {
        const original = seeded.get(workout.healthKitId);
        expect(original, `${workout.healthKitId} is not a workout that was synced`).toBeDefined();
        expect(workout.durationMinutes).toBe(original!.durationMinutes);
        expect(workout.hrAvgBpm).toBe(original!.hrAvgBpm);
        expect(workout.activeEnergyKcal).toBe(original!.activeEnergyKcal);
      }
      // Newest first, which is what an answer about "this month" reads from.
      const dates = (body.workouts as Array<{ date: string }>).map((w) => w.date);
      expect(dates[0]).toBe("2026-10-29");
      expect([...dates].sort().reverse()).toEqual(dates);
    });

    it("reports protein and calories as they were logged", async () => {
      const body = await muse.ok("get_nutrition", WINDOW);

      expect(body.averages.kcal).toBe(TRUTH.averageKcal);
      expect(body.averages.proteinG).toBe(TRUTH.averageProteinG);
      expect(body.adherence).toEqual({
        daysSynced: TRUTH.days,
        daysLogged: TRUTH.days,
        daysMeetingProteinFloor: TRUTH.daysMeetingProteinFloor,
      });

      expect(body.averages.proteinG).toBe(
        Math.round(mean(DAYS.map((day) => day.nutrition.proteinG!)) * 10) / 10,
      );
      expect(body.averages.kcal).toBe(
        Math.round(mean(DAYS.map((day) => day.nutrition.kcal!))),
      );
      // Totals only — a per-meal row never leaves the device (spec §9.1).
      expect(JSON.stringify(body)).not.toContain("items");
    });

    it("reports the weight trend the device computed, not one it re-derived", async () => {
      const body = await muse.ok("get_weight_trend", WINDOW);

      expect(body.count).toBe(TRUTH.days);
      expect(body.latest.avg7Kg).toBe(TRUTH.weightAvg7LastKg);
      expect(body.changeKg).toBe(TRUTH.changeKg);
      expect(body.rateKgPerWeek).toBe(TRUTH.rateKgPerWeek);
      expect(body.goalWeightKg).toBe(GOAL_SETTINGS.body.goalWeightKg);
      expect(body.toGoalKg).toBe(
        Math.round((TRUTH.weightAvg7LastKg - GOAL_SETTINGS.body.goalWeightKg) * 100) / 100,
      );

      const points = body.points as Array<{ date: string; avg7Kg: number }>;
      expect(points[0]!.avg7Kg).toBe(TRUTH.weightAvg7FirstKg);
      expect(points.map((p) => p.avg7Kg)).toEqual(DAYS.map((day) => day.body.weightAvg7Kg));
    });

    it("reports readiness and check-ins as the engine scored them", async () => {
      const readiness = await muse.ok("get_readiness", WINDOW);
      expect(readiness.count).toBe(TRUTH.days);
      expect(readiness.average).toBe(TRUTH.averageReadiness);
      expect(readiness.verdictCounts.trainAsPlanned).toBe(TRUTH.trainAsPlannedDays);
      expect(readiness.verdictCounts.capIntensity).toBe(TRUTH.capIntensityDays);
      expect(readiness.average).toBe(
        Math.round(mean(DAYS.map((day) => day.readiness!.score))),
      );

      const checkins = await muse.ok("get_checkins", WINDOW);
      expect(checkins.count).toBe(TRUTH.days);
      expect(checkins.averageEnergy).toBe(TRUTH.averageEnergy);
      expect(checkins.sorenessByGroup.quads.sore).toBe(TRUTH.soreQuadDays);
      expect(checkins.sorenessByGroup.chest.sore).toBe(0);
    });

    it("reports the consistency wins the device stored", async () => {
      const body = await muse.ok("get_consistency_grid", { to: MONTH_TO, weeks: 5 });

      expect(body.totals.daysSynced).toBe(TRUTH.days);
      expect(body.totals.session).toBe(TRUTH.sessionWins);
      expect(body.totals.protein).toBe(TRUTH.proteinWins);
      expect(body.totals.steps).toBe(TRUTH.stepWins);
      expect(body.totals.sleep).toBe(TRUTH.sleepWins);

      expect(body.totals.session).toBe(DAYS.filter((day) => day.wins.session).length);
      expect(body.totals.sleep).toBe(DAYS.filter((day) => day.wins.sleep).length);

      // The grid itself, not just its totals: Monday-first, one row per week.
      const grid = body.grid as Array<{ weekStart: string; days: Array<unknown> }>;
      expect(grid).toHaveLength(5);
      expect(grid.map((week) => week.weekStart)).toEqual([
        "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26",
      ]);
      for (const week of grid) expect(week.days).toHaveLength(7);
    });

    it("reports the progression on a lift, with the best set in the window", async () => {
      const body = await muse.ok("get_exercise_history", {
        ...WINDOW,
        exerciseId: "Goblet_Squat",
      });
      expect(body.count).toBe(TRUTH.squatSets);
      expect(body.best).toMatchObject({
        exerciseId: "Goblet_Squat",
        weightKg: TRUTH.bestSquatKg,
        date: TRUTH.bestSquatDate,
      });
      expect((body.sets as Array<{ weightKg: number }>).map((s) => s.weightKg)).toEqual(
        [27.5, 25, 22.5, 20],
      );
    });

    it("says how fresh the answer is, on every read tool", async () => {
      for (const name of [
        "get_today", "get_workouts", "get_nutrition", "get_weight_trend",
        "get_readiness", "get_checkins", "get_exercise_history", "get_consistency_grid",
      ]) {
        const body = await muse.ok(name, {});
        expect(body.asOf, `${name} must report asOf`).toBe(MONTH_TO);
        expect(body.schemaVersion).toBe(1);
      }
    });

    it("answers for today with the day the phone last synced", async () => {
      const body = await muse.ok("get_today", {});
      expect(body.date).toBe(MONTH_TO);
      expect(body.isLatestSynced).toBe(true);
      expect(body.rollup.training.sessionPlanned).toBe("rest");
      expect(body.rollup.nutrition.proteinG).toBe(130);
      expect(body.targets.kcal).toBe(GOAL_SETTINGS.targets.kcal);
    });
  });

  /* ------------------------------------------- 2. change a calorie target -- */

  describe("2. change a calorie target", () => {
    it("applies in the cloud, and the next read sees it", async () => {
      const before = await documentRow("goalSettings");
      expect(before!.version).toBe(1);

      const body = await muse.ok("set_targets", { kcal: 2400, proteinG: 165 });
      expect(body.status).toBe("applied");
      expect(body.document).toMatchObject({ key: "goalSettings", version: 2, updatedBy: "muse" });
      expect(body.changed).toEqual([
        { field: "kcal", from: 2200, to: 2400 },
        { field: "proteinG", from: 150, to: 165 },
      ]);

      const today = await muse.ok("get_today", {});
      expect(today.targets.kcal).toBe(2400);
      expect(today.targets.proteinG).toBe(165);

      // And in D1, not only in the answer.
      const stored = JSON.parse((await documentRow("goalSettings"))!.json);
      expect(stored.targets.kcal).toBe(2400);
    });

    it("leaves the invariants §2.1 declares intact after the change", async () => {
      const stored = JSON.parse((await documentRow("goalSettings"))!.json);
      expect(stored.targets.fatMinG).toBeGreaterThanOrEqual(60);
      expect(stored.targets.kcal).toBeGreaterThanOrEqual(1400);
      expect(stored.targets.kcal).toBeLessThanOrEqual(4000);
      expect(stored.targets.proteinMinG).toBeLessThanOrEqual(stored.targets.proteinG);
      expect(stored.dietaryRules.excludedMeats).toEqual(
        expect.arrayContaining(["pork", "beef"]),
      );
    });

    it("refuses a target outside the range, and changes nothing", async () => {
      const version = (await documentRow("goalSettings"))!.version;
      const body = await muse.rejected("set_targets", { kcal: 4200 });
      expect(body.error).toBe("invariant_violation");
      expect(body.issues[0].path).toBe("targets.kcal");
      expect(body.issues[0].message).toContain("1400...4000");
      expect((await documentRow("goalSettings"))!.version).toBe(version);
    });

    it("refuses a fat floor below 60 g, and a protein floor above the target", async () => {
      const version = (await documentRow("goalSettings"))!.version;

      const fat = await muse.rejected("set_targets", { fatMinG: 40 });
      expect(fat.issues.map((issue: { path: string }) => issue.path)).toContain(
        "targets.fatMinG",
      );

      const protein = await muse.rejected("set_targets", { proteinMinG: 999 });
      expect(protein.issues.map((issue: { path: string }) => issue.path)).toContain(
        "targets.proteinMinG",
      );

      expect((await documentRow("goalSettings"))!.version).toBe(version);
    });

    it("has no tool that could drop pork or beef from the exclusions", async () => {
      const { payload } = await muse.rpc("tools/list");
      const setTargets = (payload.result.tools as Array<Record<string, any>>).find(
        (tool) => tool.name === "set_targets",
      );
      expect(Object.keys(setTargets!.inputSchema.properties ?? {})).not.toContain(
        "dietaryRules",
      );
      const stored = JSON.parse((await documentRow("goalSettings"))!.json);
      expect(stored.dietaryRules.excludedMeats).toEqual(["pork", "beef"]);
    });
  });

  /* ------------------------------------------------- 3. swap a session, 4. meal -- */

  describe("3. swap a session, and queue a meal for the phone", () => {
    it("queues the swap for the device rather than claiming it happened", async () => {
      const body = await muse.ok("schedule_workout", {
        date: "2026-10-31",
        sessionKind: "lowerB",
      });
      expect(body.status).toBe("pending_device_apply");
      expect(body.mutationId).toHaveLength(26);
      expect(body.summary).toContain("lowerB");
    });

    it("will not schedule rest, or a session the program does not define", async () => {
      expect((await muse.rejected("schedule_workout", {
        date: "2026-10-31",
        sessionKind: "rest",
      })).error).toBe("not_schedulable");

      expect((await muse.rejected("schedule_workout", {
        date: "2026-10-31",
        sessionKind: "fullBody",
      })).error).toBe("unknown_session");
    });

    it("queues a meal of chicken and eggs, and says the phone has not written it", async () => {
      const body = await muse.ok("log_meal", {
        date: "2026-10-31",
        meal: "lunch",
        items: [
          {
            foodItemId: null,
            name: "Chicken breast",
            grams: 200,
            kcal: 330,
            proteinG: 62,
            fatG: 7,
            carbsG: 0,
          },
          {
            foodItemId: null,
            name: "Two eggs, boiled",
            grams: 110,
            kcal: 155,
            proteinG: 13,
            fatG: 11,
            carbsG: 1,
          },
        ],
      });
      expect(body.status).toBe("pending_device_apply");
      expect(body.summary).toContain("485 kcal");
      expect(body.summary).toContain("75 g protein");
    });

    it("left three mutations in the log: the applied target, and two for the phone", async () => {
      const rows = await mutationRows();
      expect(rows.map((row) => row.kind)).toEqual([
        "set_targets",
        "schedule_workout",
        "log_meal",
      ]);
      // ULIDs, so the id order is the order they must be applied in.
      expect(rows.map((row) => row.id)).toEqual([...rows.map((row) => row.id)].sort());
      expect(rows[0]!.appliedAt, "Tier 1 is applied in the cloud").not.toBeNull();
      expect(rows[1]!.appliedAt, "Tier 2 waits for the phone").toBeNull();
      expect(rows[2]!.appliedAt).toBeNull();
      for (const row of rows) expect(row.actor).toBe("muse");
    });
  });

  /* ------------------------------------------- 4. what the phone will drain -- */

  describe("4. the page the phone drains", () => {
    it("serves the three mutations to the device, newest cursor last", async () => {
      const response = await SELF.fetch(`${ORIGIN}/v1/mutations`, {
        headers: { Authorization: `Bearer ${DEVICE_TOKEN}` },
      });
      expect(response.status).toBe(200);
      const page = (await response.json()) as Record<string, any>;

      expect(page.schemaVersion).toBe(1);
      expect(page.pending).toBe(2);
      expect(page.cursor).toBe(page.mutations[page.mutations.length - 1].id);
      expect(page.mutations.map((m: { kind: string }) => m.kind)).toEqual([
        "set_targets",
        "schedule_workout",
        "log_meal",
      ]);
    });

    /**
     * The hand-over. `app/Tests/AcceptanceTests.swift` replays this exact file
     * through `MutationDrainer`, so the golden is the contract between the two
     * halves of the round trip. Only the ids and the timestamps are normalised:
     * a ULID and `new Date()` cannot be fixed from outside the Worker.
     */
    it("matches the golden page the device half replays", async () => {
      const response = await SELF.fetch(`${ORIGIN}/v1/mutations`, {
        headers: { Authorization: `Bearer ${DEVICE_TOKEN}` },
      });
      const page = (await response.json()) as Record<string, any>;

      const fixedIds = (goldenPage as any).mutations.map((m: { id: string }) => m.id);
      const normalised = {
        ...page,
        cursor: fixedIds[fixedIds.length - 1],
        mutations: page.mutations.map((mutation: Record<string, any>, index: number) => ({
          ...mutation,
          id: fixedIds[index],
          createdAt: (goldenPage as any).mutations[index].createdAt,
          appliedAt:
            mutation.appliedAt === null
              ? null
              : (goldenPage as any).mutations[index].appliedAt,
        })),
      };
      expect(normalised).toEqual(goldenPage);
    });

    it("acks only what the device says it applied, and moves the cursor", async () => {
      const rows = await mutationRows();
      const ids = rows.map((row) => row.id);

      const ack = await SELF.fetch(`${ORIGIN}/v1/mutations/ack`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${DEVICE_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          schemaVersion: 1,
          ids,
          appliedAt: "2026-10-31T20:15:00-04:00",
        }),
      });
      expect(ack.status).toBe(200);
      const outcome = (await ack.json()) as Record<string, any>;
      // The two Tier-2 ids move; the Tier-1 one the Worker already stamped
      // comes back as `alreadyApplied`, so an ack cannot rewrite its instant.
      expect(outcome.acked).toEqual([ids[1], ids[2]]);
      expect(outcome.alreadyApplied).toEqual([ids[0]]);
      expect(outcome.unknown).toEqual([]);
      expect(outcome.pending).toBe(0);

      const after = await SELF.fetch(`${ORIGIN}/v1/mutations?since=${ids[2]}`, {
        headers: { Authorization: `Bearer ${DEVICE_TOKEN}` },
      });
      expect(((await after.json()) as Record<string, any>).mutations).toEqual([]);
    });
  });

  /* ------------------------- 5. the invariant a session swap can break -- */

  describe("5. no two non-rest days train the same region inside 48 h", () => {
    it("refuses a week that puts Upper A beside Upper B", async () => {
      const body = await muse.rejected("update_program", {
        program: { ...PROGRAM, days: [
          { weekday: 1, kind: "upperA" },
          { weekday: 2, kind: "upperB" },
          { weekday: 3, kind: "rest" },
          { weekday: 4, kind: "lowerA" },
          { weekday: 5, kind: "lowerB" },
          { weekday: 6, kind: "rest" },
          { weekday: 7, kind: "rest" },
        ] },
      });
      expect(body.error).toBe("invariant_violation");
      expect(JSON.stringify(body.issues)).toContain("upperBody");
    });

    it("refuses a week that wraps Sunday into Monday", async () => {
      const body = await muse.rejected("update_program", {
        program: { ...PROGRAM, days: [
          { weekday: 1, kind: "lowerA" },
          { weekday: 2, kind: "upperA" },
          { weekday: 3, kind: "rest" },
          { weekday: 4, kind: "upperB" },
          { weekday: 5, kind: "rest" },
          { weekday: 6, kind: "rest" },
          { weekday: 7, kind: "lowerB" },
        ] },
      });
      expect(body.error).toBe("invariant_violation");
      expect(JSON.stringify(body.issues)).toContain("lowerBody");
    });

    it("accepts a legal week, and the program it stores is the one it was sent", async () => {
      const body = await muse.ok("update_program", {
        program: { ...PROGRAM, days: [
          { weekday: 1, kind: "upperA" },
          { weekday: 2, kind: "lowerA" },
          { weekday: 3, kind: "rest" },
          { weekday: 4, kind: "upperB" },
          { weekday: 5, kind: "rest" },
          { weekday: 6, kind: "lowerB" },
          { weekday: 7, kind: "rest" },
        ] },
      });
      expect(body.status).toBe("applied");

      const stored = JSON.parse((await documentRow("program"))!.json);
      expect(stored.days.map((d: { kind: string }) => d.kind)).toEqual([
        "upperA", "lowerA", "rest", "upperB", "rest", "lowerB", "rest",
      ]);
    });

    it("never recommends what it cannot store: a rejection names the offending days", async () => {
      const body = await muse.rejected("update_program", {
        program: { ...PROGRAM, days: [
          { weekday: 1, kind: "lowerA" },
          { weekday: 2, kind: "lowerB" },
          { weekday: 3, kind: "rest" },
          { weekday: 4, kind: "upperA" },
          { weekday: 5, kind: "upperB" },
          { weekday: 6, kind: "rest" },
          { weekday: 7, kind: "rest" },
        ] },
      });
      const issues = JSON.stringify(body.issues);
      expect(issues).toContain("lowerBody");
      expect(issues).toContain("upperBody");
    });
  });
});
