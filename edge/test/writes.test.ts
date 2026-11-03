/**
 * The write tools: Tier 1 applied here, Tier 2 queued for the phone.
 *
 * Every guardrail is tested rejecting, not just the happy path — Muse writes
 * with no confirmation, so the rejections are the feature.
 */
import { beforeEach, describe, expect, it } from "vitest";
import { readFlags, readGoalSettings, readProgram } from "../src/db/documents";
import { listSuggestions } from "../src/db/suggestions";
import { testEnv } from "./env";
import { GOAL_SETTINGS, PROGRAM, programWith, STAPLES } from "./fixtures";
import {
  documentRow,
  mutationRows,
  seedDocuments,
  write,
  writeFails,
  writeTool,
} from "./helpers";

const SORENESS = {
  chest: "none",
  back: "mild",
  shoulders: "none",
  arms: "none",
  quads: "sore",
  hamstrings: "mild",
  glutes: "none",
  core: "none",
} as const;

describe("the write tool surface", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("offers every kind docs/EXPORT_SCHEMA.md §3 declares, and no delete tool", () => {
    expect(
      [
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
      ].every((name) => writeTool(name)),
    ).toBe(true);
  });

  it("refuses every write when museWritesEnabled is off", async () => {
    await seedDocuments({ flags: { museWritesEnabled: false } });
    for (const name of ["set_targets", "log_water", "trigger_export"]) {
      const error = await writeFails(name, { kcal: 2000, date: "2026-11-03", ml: 500 });
      expect(error.code).toBe("writes_disabled");
    }
    expect(await mutationRows()).toHaveLength(0);
  });
});

/* -------------------------------------------------------------- Tier 1 --- */

describe("set_targets", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("patches only the fields it was given, bumps the version and logs the change", async () => {
    const result = await write("set_targets", { kcal: 2000 });

    expect(result.status).toBe("applied");
    expect(result.document).toMatchObject({ key: "goalSettings", version: 2, updatedBy: "muse" });
    expect(result.changed).toEqual([{ field: "kcal", from: 2200, to: 2000 }]);
    expect(result.summary).toBe("targets: kcal 2200 → 2000");

    const stored = await readGoalSettings(testEnv.DB);
    expect(stored?.targets).toEqual({ ...GOAL_SETTINGS.targets, kcal: 2000 });

    const [mutation] = await mutationRows();
    expect(mutation).toMatchObject({ kind: "set_targets", actor: "muse" });
    // §3: the payload is the partial, not the merged document.
    expect(JSON.parse(mutation?.payload ?? "{}")).toEqual({ kcal: 2000 });
    // Tier 1 is applied by the Worker, so it is marked applied immediately.
    expect(mutation?.appliedAt).not.toBeNull();
    expect(result.mutationId).toBe(mutation?.id);
  });

  it("rejects a calorie target under the floor, naming the value", async () => {
    const error = await writeFails("set_targets", { kcal: 1399 });
    expect(error.code).toBe("invariant_violation");
    expect(error.detail.issues).toEqual([
      { path: "targets.kcal", message: "targets.kcal must be within 1400...4000, found 1399" },
    ]);
    expect((await documentRow("goalSettings"))?.version).toBe(1);
    expect(await mutationRows()).toHaveLength(0);
  });

  it("rejects a calorie target over the ceiling", async () => {
    expect((await writeFails("set_targets", { kcal: 4001 })).code).toBe("invariant_violation");
  });

  it("rejects a fat floor under 60 g", async () => {
    const error = await writeFails("set_targets", { fatMinG: 45 });
    expect(error.detail.issues).toMatchObject([{ path: "targets.fatMinG" }]);
  });

  it("rejects a protein floor above the protein target it is merged into", async () => {
    // 200 against the stored proteinG of 150: the merge is what breaks it, which
    // is why the invariant runs on the merged document and not on the patch.
    const error = await writeFails("set_targets", { proteinMinG: 200 });
    expect(error.detail.issues).toMatchObject([{ path: "targets.proteinMinG" }]);
  });

  it("accepts a pair of values that are only legal together", async () => {
    const result = await write("set_targets", { proteinG: 200, proteinMinG: 190 });
    expect(result.status).toBe("applied");
  });

  it("rejects a fractional target — every target is an integer on the device", async () => {
    const error = await writeFails("set_targets", { kcal: 2000.5 });
    expect(error.code).toBe("contract_violation");
    expect(error.detail.issues).toMatchObject([{ path: "kcal" }]);
  });

  it("rejects an unknown field rather than dropping it", async () => {
    const error = await writeFails("set_targets", { kcal: 2000, carbsG: 250 });
    expect(error.code).toBe("contract_violation");
    expect(JSON.stringify(error.detail.issues)).toContain("carbsG");
  });

  it("rejects a call that changes nothing", async () => {
    expect((await writeFails("set_targets", {})).code).toBe("nothing_to_write");
  });

  it("honours If-Match, and reports the version it actually found", async () => {
    await write("set_targets", { kcal: 2000 });
    const error = await writeFails("set_targets", { kcal: 2100, ifMatch: 1 });
    expect(error.code).toBe("version_conflict");
    expect(error.detail).toMatchObject({ document: "goalSettings", expected: 1, currentVersion: 2 });
    expect((await readGoalSettings(testEnv.DB))?.targets.kcal).toBe(2000);
  });

  it("accepts a matching If-Match", async () => {
    const result = await write("set_targets", { kcal: 2100, ifMatch: 1 });
    expect(result.document).toMatchObject({ version: 2 });
  });

  it("refuses to write when goalSettings is unreadable", async () => {
    await testEnv.DB.prepare(`DELETE FROM documents WHERE key = 'goalSettings'`).run();
    expect((await writeFails("set_targets", { kcal: 2000 })).code).toBe("missing_document");
  });
});

describe("update_program", () => {
  beforeEach(async () => {
    await seedDocuments({ program: null });
  });

  it("writes a legal week, creating the document that was never seeded", async () => {
    const result = await write("update_program", { program: PROGRAM });
    expect(result.status).toBe("applied");
    expect(result.document).toMatchObject({ key: "program", version: 1, updatedBy: "muse" });
    expect(result.summary).toContain("Mon upperA");
    expect((await readProgram(testEnv.DB))?.name).toBe("Upper/Lower 4-day");

    const [mutation] = await mutationRows();
    expect(mutation?.kind).toBe("update_program");
    // §3: the payload is the full program body.
    expect(JSON.parse(mutation?.payload ?? "{}")).toEqual(PROGRAM);
  });

  it("rejects two upper days 24 h apart, naming the offending pair", async () => {
    const illegal = programWith([
      { weekday: 1, kind: "upperA" },
      { weekday: 2, kind: "upperB" },
      { weekday: 3, kind: "rest" },
      { weekday: 4, kind: "lowerA" },
      { weekday: 5, kind: "rest" },
      { weekday: 6, kind: "lowerB" },
      { weekday: 7, kind: "rest" },
    ]);
    const error = await writeFails("update_program", { program: illegal });
    expect(error.code).toBe("invariant_violation");
    expect(error.detail.issues).toEqual([
      {
        path: "days.1",
        message: "weekdays 1 (upperA) and 2 (upperB) both train upperBody less than 48 h apart",
      },
    ]);
    expect(await documentRow("program")).toBeNull();
    expect(await mutationRows()).toHaveLength(0);
  });

  it("accepts the same region exactly 48 h apart", async () => {
    const legal = programWith([
      { weekday: 1, kind: "upperA" },
      { weekday: 2, kind: "lowerA" },
      { weekday: 3, kind: "upperB" },
      { weekday: 4, kind: "lowerB" },
      { weekday: 5, kind: "rest" },
      { weekday: 6, kind: "rest" },
      { weekday: 7, kind: "rest" },
    ]);
    expect((await write("update_program", { program: legal })).status).toBe("applied");
  });

  it("rejects a week whose Sunday collides with its Monday", async () => {
    const wrapped = programWith([
      { weekday: 1, kind: "lowerA" },
      { weekday: 2, kind: "upperA" },
      { weekday: 3, kind: "rest" },
      { weekday: 4, kind: "upperB" },
      { weekday: 5, kind: "rest" },
      { weekday: 6, kind: "rest" },
      { weekday: 7, kind: "lowerB" },
    ]);
    const error = await writeFails("update_program", { program: wrapped });
    expect(error.detail.issues).toMatchObject([{ path: "days.7" }]);
  });

  it("rejects a week that is not seven days", async () => {
    const error = await writeFails("update_program", {
      program: { ...PROGRAM, days: PROGRAM.days.slice(0, 6) },
    });
    // The contract's own `.length(7)` catches this before the invariants do.
    expect(error.code).toBe("contract_violation");
    expect(JSON.stringify(error.detail.issues)).toContain("days");
  });

  it("rejects a weekday outside 1–7", async () => {
    const error = await writeFails("update_program", {
      program: { ...PROGRAM, days: [...PROGRAM.days.slice(0, 6), { weekday: 8, kind: "rest" }] },
    });
    expect(error.code).toBe("contract_violation");
  });

  it("rejects a day whose kind is not a session kind", async () => {
    const error = await writeFails("update_program", {
      program: {
        ...PROGRAM,
        days: [{ weekday: 1, kind: "legs" }, ...PROGRAM.days.slice(1)],
      },
    });
    expect(error.code).toBe("contract_violation");
    expect(JSON.stringify(error.detail.issues)).toContain("days.0.kind");
  });

  it("rejects a program carrying envelope keys in its body", async () => {
    const error = await writeFails("update_program", {
      program: { ...PROGRAM, version: 3, updatedBy: "muse" },
    });
    expect(error.code).toBe("contract_violation");
  });

  it("can restructure Upper/Lower into full-body and back (spec §3)", async () => {
    const fullBody = programWith([
      { weekday: 1, kind: "fullBody" },
      { weekday: 2, kind: "rest" },
      { weekday: 3, kind: "zone2" },
      { weekday: 4, kind: "fullBody" },
      { weekday: 5, kind: "rest" },
      { weekday: 6, kind: "zone2" },
      { weekday: 7, kind: "rest" },
    ]);
    expect((await write("update_program", { program: fullBody })).status).toBe("applied");
    expect((await write("update_program", { program: PROGRAM })).document).toMatchObject({
      version: 2,
    });
  });

  it("flips a week to deload without touching the sessions", async () => {
    await write("update_program", { program: PROGRAM });
    const result = await write("update_program", {
      program: { ...PROGRAM, deload: { active: true, loadFactor: 0.6, volumeFactor: 0.5 } },
    });
    expect(result.changed).toContainEqual({ field: "deload.active", from: false, to: true });
    expect((await readProgram(testEnv.DB))?.deload.active).toBe(true);
  });

  it("honours If-Match on a document that does not exist yet", async () => {
    const error = await writeFails("update_program", { program: PROGRAM, ifMatch: 1 });
    expect(error.detail).toMatchObject({ expected: 1, currentVersion: 0 });
    expect((await write("update_program", { program: PROGRAM, ifMatch: 0 })).status).toBe("applied");
  });
});

describe("set_flag", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("flips a boolean flag and logs `{ key, value }`", async () => {
    const result = await write("set_flag", { key: "rawDetailSyncEnabled", value: true });
    expect(result.status).toBe("applied");
    expect(result.summary).toBe("flags.rawDetailSyncEnabled: false → true");
    expect((await readFlags(testEnv.DB))?.rawDetailSyncEnabled).toBe(true);
    expect(JSON.parse((await mutationRows())[0]?.payload ?? "{}")).toEqual({
      key: "rawDetailSyncEnabled",
      value: true,
    });
  });

  it("sets museWriteMode, which is the one flag that is not a boolean", async () => {
    const result = await write("set_flag", { key: "museWriteMode", value: "propose" });
    expect(result.status).toBe("applied");
    expect((await readFlags(testEnv.DB))?.museWriteMode).toBe("propose");
  });

  it("rejects a boolean written to museWriteMode", async () => {
    const error = await writeFails("set_flag", { key: "museWriteMode", value: true });
    expect(error.code).toBe("contract_violation");
    expect((await readFlags(testEnv.DB))?.museWriteMode).toBe("apply");
  });

  it("rejects a string written to a boolean flag", async () => {
    expect(
      (await writeFails("set_flag", { key: "rawDetailSyncEnabled", value: "yes" })).code,
    ).toBe("contract_violation");
  });

  it("rejects an unknown flag", async () => {
    expect((await writeFails("set_flag", { key: "darkMode", value: true })).code).toBe(
      "contract_violation",
    );
  });

  it("can switch Muse's own writes off — and cannot switch them back on", async () => {
    expect((await write("set_flag", { key: "museWritesEnabled", value: false })).status).toBe(
      "applied",
    );
    const error = await writeFails("set_flag", { key: "museWritesEnabled", value: true });
    expect(error.code).toBe("writes_disabled");
  });
});

describe("set_staples", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("queues for the device, because the staples list is the phone's own state", async () => {
    const result = await write("set_staples", { staples: STAPLES });
    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toContain("4 items");

    const [mutation] = await mutationRows();
    expect(mutation?.kind).toBe("set_staples");
    expect(mutation?.appliedAt).toBeNull();
    expect(JSON.parse(mutation?.payload ?? "{}").staples).toHaveLength(4);
    // No document row: there is no `staples` document in D1.
    expect(await documentRow("staples")).toBeNull();
  });

  it("accepts an empty list — that is how the staples are cleared", async () => {
    expect((await write("set_staples", { staples: [] })).status).toBe("pending_device_apply");
  });

  it("rejects a food whose source is not one of the four", async () => {
    const error = await writeFails("set_staples", {
      staples: [{ ...STAPLES[0], source: "guess" }],
    });
    expect(error.code).toBe("contract_violation");
    expect(JSON.stringify(error.detail.issues)).toContain("source");
  });

  it("rejects per-portion macros dressed up as per-100 g fields", async () => {
    const error = await writeFails("set_staples", {
      staples: [{ ...STAPLES[0], kcal: 650 }],
    });
    expect(error.code).toBe("contract_violation");
  });
});

/* -------------------------------------------------------------- Tier 2 --- */

describe("the Tier-2 tools", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("log_meal queues and never claims the Health write landed", async () => {
    const result = await write("log_meal", {
      date: "2026-11-03",
      meal: "lunch",
      items: [
        { name: "Chicken breast", grams: 200, kcal: 330, proteinG: 62, fatG: 7, carbsG: 0 },
        { foodItemId: "staple_chicken_rice_veg", name: "Rice", grams: 180, kcal: 234, proteinG: 5, fatG: 1, carbsG: 51 },
      ],
    });

    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toBe("lunch on 2026-11-03: 2 items, 564 kcal, 67 g protein");
    expect(result.hint).toContain("Do not report it as logged");
    expect(result.pendingMutations).toBe(1);

    const [mutation] = await mutationRows();
    expect(mutation?.kind).toBe("log_meal");
    expect(mutation?.appliedAt).toBeNull();
  });

  it("log_meal rejects an unknown meal slot", async () => {
    const error = await writeFails("log_meal", {
      date: "2026-11-03",
      meal: "brunch",
      items: [{ name: "Eggs", grams: 100, kcal: 148, proteinG: 13, fatG: 11, carbsG: 1 }],
    });
    expect(error.code).toBe("contract_violation");
    expect(JSON.stringify(error.detail.issues)).toContain("meal");
  });

  it("log_meal rejects a meal with no items", async () => {
    expect(
      (await writeFails("log_meal", { date: "2026-11-03", meal: "lunch", items: [] })).code,
    ).toBe("contract_violation");
  });

  it("log_meal rejects a date that is not YYYY-MM-DD", async () => {
    const error = await writeFails("log_meal", {
      date: "3 November 2026",
      meal: "lunch",
      items: [{ name: "Eggs", grams: 100, kcal: 148, proteinG: 13, fatG: 11, carbsG: 1 }],
    });
    expect(error.detail.issues).toMatchObject([{ path: "date" }]);
  });

  it("log_water queues millilitres", async () => {
    const result = await write("log_water", { date: "2026-11-03", ml: 500 });
    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toBe("water on 2026-11-03: 500 ml");
  });

  it.each([0, -250, 10_001])("log_water rejects %i ml", async (ml) => {
    expect((await writeFails("log_water", { date: "2026-11-03", ml })).code).toBe(
      "contract_violation",
    );
  });

  it("log_top_set queues weight and reps", async () => {
    const result = await write("log_top_set", {
      date: "2026-11-03",
      exerciseId: "Goblet_Squat",
      weightKg: 24,
      reps: 12,
    });
    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toBe("Goblet_Squat 24 kg × 12 on 2026-11-03");
  });

  it("log_top_set rejects zero reps and a fractional rep count", async () => {
    for (const reps of [0, 8.5]) {
      const error = await writeFails("log_top_set", {
        date: "2026-11-03",
        exerciseId: "Goblet_Squat",
        weightKg: 24,
        reps,
      });
      expect(error.code).toBe("contract_violation");
    }
  });

  it("log_checkin queues energy and all eight soreness groups", async () => {
    const result = await write("log_checkin", {
      date: "2026-11-03",
      energy: 4,
      soreness: SORENESS,
    });
    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toBe("check-in on 2026-11-03: energy 4, sore: quads");
  });

  it("log_checkin rejects energy outside 1–5", async () => {
    for (const energy of [0, 6]) {
      const error = await writeFails("log_checkin", {
        date: "2026-11-03",
        energy,
        soreness: SORENESS,
      });
      expect(error.detail.issues).toMatchObject([{ path: "energy" }]);
    }
  });

  it("log_checkin rejects a missing muscle group — absent is not `none`", async () => {
    const { core, ...withoutCore } = SORENESS;
    void core;
    const error = await writeFails("log_checkin", {
      date: "2026-11-03",
      energy: 4,
      soreness: withoutCore,
    });
    expect(error.code).toBe("contract_violation");
    expect(JSON.stringify(error.detail.issues)).toContain("core");
  });

  it("log_checkin rejects a soreness level that is not none/mild/sore", async () => {
    const error = await writeFails("log_checkin", {
      date: "2026-11-03",
      energy: 4,
      soreness: { ...SORENESS, quads: "agony" },
    });
    expect(error.detail.issues).toMatchObject([{ path: "soreness.quads" }]);
  });

  it("schedule_workout queues a session the program defines", async () => {
    const result = await write("schedule_workout", {
      date: "2026-11-09",
      sessionKind: "upperA",
    });
    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toBe("Upper A (upperA) to the Watch for 2026-11-09");
  });

  it("schedule_workout refuses a session the program does not define", async () => {
    const error = await writeFails("schedule_workout", {
      date: "2026-11-09",
      sessionKind: "fullBody",
    });
    expect(error.code).toBe("unknown_session");
    expect(error.detail.definedSessions).toContain("upperA");
  });

  it("schedule_workout refuses `rest`", async () => {
    const error = await writeFails("schedule_workout", {
      date: "2026-11-09",
      sessionKind: "rest",
    });
    expect(error.code).toBe("not_schedulable");
  });

  it("schedule_workout refuses when there is no program at all", async () => {
    await seedDocuments({ program: null });
    const error = await writeFails("schedule_workout", {
      date: "2026-11-09",
      sessionKind: "upperA",
    });
    expect(error.code).toBe("missing_document");
  });

  it("trigger_export queues with an empty payload", async () => {
    const result = await write("trigger_export", {});
    expect(result.status).toBe("pending_device_apply");
    expect(JSON.parse((await mutationRows())[0]?.payload ?? "null")).toEqual({});
  });

  it("every Tier-2 tool answers pending_device_apply and leaves appliedAt null", async () => {
    await write("log_water", { date: "2026-11-03", ml: 250 });
    await write("log_top_set", {
      date: "2026-11-03",
      exerciseId: "Goblet_Squat",
      weightKg: 24,
      reps: 10,
    });
    await write("log_checkin", { date: "2026-11-03", energy: 3, soreness: SORENESS });
    await write("schedule_workout", { date: "2026-11-10", sessionKind: "lowerA" });
    await write("trigger_export", {});

    const rows = await mutationRows();
    expect(rows).toHaveLength(5);
    expect(rows.every((row) => row.appliedAt === null)).toBe(true);
    // ULIDs sort in the order they were appended, which is the order the device
    // must apply them in.
    expect(rows.map((row) => row.id)).toEqual([...rows.map((row) => row.id)].sort());
  });

  it("asks the phone to wake, and queues anyway when the push fails", async () => {
    const calls: string[] = [];
    const ok = await write(
      "log_water",
      { date: "2026-11-03", ml: 250 },
      {
        wake: async () => {
          calls.push("wake");
          return { sent: 1, failed: 0 };
        },
      },
    );
    expect(calls).toEqual(["wake"]);
    expect(ok.devicePush).toEqual({ sent: 1, failed: 0 });

    const broken = await write(
      "log_water",
      { date: "2026-11-03", ml: 250 },
      {
        wake: async () => {
          throw new Error("APNs said no");
        },
      },
    );
    // Correctness never depends on the push: the mutation is queued regardless.
    expect(broken.status).toBe("pending_device_apply");
    expect(broken.devicePush).toEqual({ error: "APNs said no" });
    expect(await mutationRows()).toHaveLength(2);
  });
});

/* ------------------------------------------------- propose mode and accept -- */

describe("museWriteMode: propose", () => {
  beforeEach(async () => {
    await seedDocuments({ flags: { museWriteMode: "propose" } });
  });

  it("records a Tier-1 write as a suggestion instead of making it", async () => {
    const result = await write("set_targets", { kcal: 2000 });

    expect(result.status).toBe("proposed");
    expect(result.writeMode).toBe("propose");
    expect(result.summary).toBe("targets: kcal 2200 → 2000");
    expect(result.suggestionId).toMatch(/^muse_/);

    // Nothing changed, and a proposal is not a change, so nothing is logged.
    expect((await documentRow("goalSettings"))?.version).toBe(1);
    expect((await readGoalSettings(testEnv.DB))?.targets.kcal).toBe(2200);
    expect(await mutationRows()).toHaveLength(0);

    const pending = await listSuggestions(testEnv.DB, { status: "pending" });
    expect(pending).toHaveLength(1);
    expect(pending[0]).toMatchObject({ source: "muse", kind: "set_targets", status: "pending" });
  });

  it("still rejects an illegal write rather than proposing it", async () => {
    const error = await writeFails("set_targets", { kcal: 900 });
    expect(error.code).toBe("invariant_violation");
    expect(await listSuggestions(testEnv.DB)).toHaveLength(0);
  });

  it("proposes a program rewrite, having checked §F5 first", async () => {
    const result = await write("update_program", { program: PROGRAM });
    expect(result.status).toBe("proposed");
    expect((await documentRow("program"))?.version).toBe(1);

    const illegal = programWith([
      { weekday: 1, kind: "lowerA" },
      { weekday: 2, kind: "lowerB" },
      { weekday: 3, kind: "rest" },
      { weekday: 4, kind: "upperA" },
      { weekday: 5, kind: "rest" },
      { weekday: 6, kind: "rest" },
      { weekday: 7, kind: "rest" },
    ]);
    expect((await writeFails("update_program", { program: illegal })).code).toBe(
      "invariant_violation",
    );
  });

  it("proposes a staples change rather than queueing it", async () => {
    const result = await write("set_staples", { staples: STAPLES });
    expect(result.status).toBe("proposed");
    expect(await mutationRows()).toHaveLength(0);
  });

  it("leaves Tier-2 logging alone — a log is a record, not a proposal", async () => {
    const result = await write("log_water", { date: "2026-11-03", ml: 400 });
    expect(result.status).toBe("pending_device_apply");
    expect(await mutationRows()).toHaveLength(1);
  });

  it("applies the proposal on accept, and will not apply it twice", async () => {
    const proposed = await write("set_targets", { kcal: 2000, fatMinG: 65 });
    const accepted = await write("accept_suggestion", {
      suggestionId: proposed.suggestionId,
    });

    expect(accepted.status).toBe("applied");
    expect(accepted.summary).toBe("accepted: targets: kcal 2200 → 2000, fatMinG 60 → 65");
    const stored = await readGoalSettings(testEnv.DB);
    expect(stored?.targets.kcal).toBe(2000);
    expect(stored?.targets.fatMinG).toBe(65);
    expect(stored?.version).toBe(2);

    const kinds = (await mutationRows()).map((row) => row.kind);
    expect(kinds).toEqual(["accept_suggestion", "set_targets"]);

    const again = await writeFails("accept_suggestion", {
      suggestionId: proposed.suggestionId,
    });
    expect(again.code).toBe("already_decided");
    expect((await readGoalSettings(testEnv.DB))?.version).toBe(2);
  });

  it("accepts a proposal even though the mode would otherwise propose", async () => {
    const proposed = await write("set_flag", { key: "rawDetailSyncEnabled", value: true });
    const accepted = await write("accept_suggestion", { suggestionId: proposed.suggestionId });
    expect(accepted.status).toBe("applied");
    expect((await readFlags(testEnv.DB))?.rawDetailSyncEnabled).toBe(true);
    // And the mode itself is untouched, so later writes still propose.
    expect((await readFlags(testEnv.DB))?.museWriteMode).toBe("propose");
  });
});

describe("accept_suggestion", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("rejects an id it does not hold, and lists what is open", async () => {
    await seedDocuments({ flags: { museWriteMode: "propose" } });
    const proposed = await write("set_targets", { kcal: 2000 });

    const error = await writeFails("accept_suggestion", { suggestionId: "nope" });
    expect(error.code).toBe("unknown_suggestion");
    expect(error.detail.openSuggestions).toMatchObject([{ id: proposed.suggestionId }]);
    // No mutation: a guessed id must never become a queued instruction, which
    // the phone would fail to apply and then stop draining on.
    expect(await mutationRows()).toHaveLength(0);
  });

  it("queues a suggestion only the phone can apply", async () => {
    await testEnv.DB.prepare(
      `INSERT INTO suggestions (id, createdAt, source, kind, text, actionKind, actionPayload, status, decidedAt)
       VALUES ('sug_1', '2026-11-03T08:00:00-05:00', 'device', 'calorieAdjust',
               'Weight is falling faster than planned', NULL, NULL, 'pending', NULL)`,
    ).run();

    const result = await write("accept_suggestion", { suggestionId: "sug_1" });
    expect(result.status).toBe("pending_device_apply");
    expect(result.summary).toBe("accepted: Weight is falling faster than planned");
    expect((await mutationRows()).map((row) => row.kind)).toEqual([
      "accept_suggestion",
      "accept_suggestion",
    ]);
  });

  it("applies a device suggestion that carries its own change", async () => {
    await testEnv.DB.prepare(
      `INSERT INTO suggestions (id, createdAt, source, kind, text, actionKind, actionPayload, status, decidedAt)
       VALUES ('sug_2', '2026-11-03T08:00:00-05:00', 'device', 'calorieAdjust',
               'Hold calories at 2,050', 'set_targets', '{"kcal":2050}', 'pending', NULL)`,
    ).run();

    const result = await write("accept_suggestion", { suggestionId: "sug_2" });
    expect(result.status).toBe("applied");
    expect((await readGoalSettings(testEnv.DB))?.targets.kcal).toBe(2050);
  });
});
