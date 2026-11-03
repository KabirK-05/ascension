/**
 * Stream B's device half: the four endpoints the phone drives
 * (docs/TECH_STACK.md §2.3).
 *
 * `packages/SyncClient` is already written against these envelopes, so the
 * shapes here are the ones it decodes — a drift in either direction breaks the
 * loop silently, in both directions.
 */
import { SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { testEnv } from "./env";
import { GOAL_SETTINGS, PROGRAM, programWith } from "./fixtures";
import { mutationRows, seedDocuments, write } from "./helpers";

const ORIGIN = "http://localhost:8787";
const TOKEN = "test-device-token";

async function call(
  path: string,
  init: RequestInit & { token?: string | null } = {},
): Promise<{ status: number; body: Record<string, any> }> {
  const { token = TOKEN, ...rest } = init;
  const headers = new Headers(rest.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  if (rest.body) headers.set("Content-Type", "application/json");
  const response = await SELF.fetch(`${ORIGIN}${path}`, { ...rest, headers });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : {} };
}

describe("GET /v1/mutations", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("needs the device token", async () => {
    const { status, body } = await call("/v1/mutations", { token: null });
    expect(status).toBe(401);
    expect(body.error).toBe("unauthorized");
    expect((await call("/v1/mutations", { token: "wrong" })).status).toBe(401);
  });

  it("serves the tail in ULID order, with a cursor to come back with", async () => {
    await write("log_water", { date: "2026-11-03", ml: 250 });
    await write("set_targets", { kcal: 2000 });
    await write("log_top_set", {
      date: "2026-11-03",
      exerciseId: "Goblet_Squat",
      weightKg: 24,
      reps: 12,
    });

    const { status, body } = await call("/v1/mutations");
    expect(status).toBe(200);
    expect(body.schemaVersion).toBe(1);
    expect(body.mutations.map((row: any) => row.kind)).toEqual([
      "log_water",
      "set_targets",
      "log_top_set",
    ]);
    expect(body.cursor).toBe(body.mutations.at(-1).id);
    // Tier 1 arrives already applied; Tier 2 arrives waiting.
    expect(body.mutations[0]).toMatchObject({ actor: "muse", appliedAt: null, appliedResult: null });
    expect(body.mutations[1].appliedAt).not.toBeNull();
    expect(body.pending).toBe(2);
  });

  it("carries every field the contract declares, and no more", async () => {
    await write("trigger_export", {});
    const { body } = await call("/v1/mutations");
    expect(Object.keys(body.mutations[0]).sort()).toEqual([
      "actor",
      "appliedAt",
      "appliedResult",
      "createdAt",
      "id",
      "kind",
      "payload",
    ]);
  });

  it("pages from a cursor, and serves Tier-1 rows too — the phone catches up offline", async () => {
    await write("set_targets", { kcal: 2000 });
    const first = await call("/v1/mutations");
    await write("log_water", { date: "2026-11-03", ml: 250 });

    const { body } = await call(`/v1/mutations?since=${first.body.cursor}`);
    expect(body.mutations.map((row: any) => row.kind)).toEqual(["log_water"]);
  });

  it("answers an empty tail with a null cursor rather than an error", async () => {
    const { status, body } = await call("/v1/mutations");
    expect(status).toBe(200);
    expect(body).toMatchObject({ mutations: [], cursor: null, pending: 0 });
  });

  it("rejects a cursor that is not a ULID", async () => {
    const { status, body } = await call("/v1/mutations?since=yesterday");
    expect(status).toBe(400);
    expect(body.error).toBe("invalid_cursor");
  });
});

describe("POST /v1/mutations/ack", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("stamps appliedAt from the device's own instant", async () => {
    await write("log_water", { date: "2026-11-03", ml: 250 });
    const [queued] = await mutationRows();
    const appliedAt = "2026-11-03T22:15:00-05:00";

    const { status, body } = await call("/v1/mutations/ack", {
      method: "POST",
      body: JSON.stringify({ schemaVersion: 1, ids: [queued!.id], appliedAt }),
    });

    expect(status).toBe(200);
    expect(body).toMatchObject({ acked: [queued!.id], alreadyApplied: [], unknown: [], pending: 0 });
    expect((await mutationRows())[0]?.appliedAt).toBe(appliedAt);
  });

  it("is safe to repeat, and never moves a timestamp already recorded", async () => {
    await write("log_water", { date: "2026-11-03", ml: 250 });
    const [queued] = await mutationRows();
    const first = "2026-11-03T22:15:00-05:00";

    await call("/v1/mutations/ack", {
      method: "POST",
      body: JSON.stringify({ ids: [queued!.id], appliedAt: first }),
    });
    const { body } = await call("/v1/mutations/ack", {
      method: "POST",
      body: JSON.stringify({ ids: [queued!.id], appliedAt: "2026-11-04T09:00:00-05:00" }),
    });

    expect(body.alreadyApplied).toEqual([queued!.id]);
    expect(body.acked).toEqual([]);
    expect((await mutationRows())[0]?.appliedAt).toBe(first);
  });

  it("names an id it has never seen instead of failing the whole ack", async () => {
    await write("log_water", { date: "2026-11-03", ml: 250 });
    const [queued] = await mutationRows();
    const { body } = await call("/v1/mutations/ack", {
      method: "POST",
      body: JSON.stringify({
        ids: [queued!.id, "01JC8X9Y2K3M4N5P6Q7R8S9TZZ"],
        appliedAt: "2026-11-03T22:15:00-05:00",
      }),
    });
    expect(body.acked).toEqual([queued!.id]);
    expect(body.unknown).toEqual(["01JC8X9Y2K3M4N5P6Q7R8S9TZZ"]);
  });

  it("rejects an ack with no timestamp, or with an id that is not a ULID", async () => {
    expect(
      (await call("/v1/mutations/ack", { method: "POST", body: JSON.stringify({ ids: ["x"] }) }))
        .status,
    ).toBe(400);
    expect(
      (
        await call("/v1/mutations/ack", {
          method: "POST",
          body: JSON.stringify({ ids: ["short"], appliedAt: "2026-11-03T22:15:00-05:00" }),
        })
      ).status,
    ).toBe(400);
  });
});

describe("GET|PUT /v1/documents/<key>", () => {
  beforeEach(async () => {
    await seedDocuments();
  });

  it("serves a document with its envelope composed back in", async () => {
    const { status, body } = await call("/v1/documents/goalSettings");
    expect(status).toBe(200);
    expect(body.document).toMatchObject({
      key: "goalSettings",
      version: 1,
      updatedBy: "system",
      targets: GOAL_SETTINGS.targets,
    });
  });

  it("404s a document that has never been written, and an unknown key", async () => {
    await seedDocuments({ program: null });
    expect((await call("/v1/documents/program")).status).toBe(404);
    const unknown = await call("/v1/documents/staples");
    expect(unknown.status).toBe(404);
    expect(unknown.body.known).toEqual(["goalSettings", "program", "flags"]);
  });

  it("writes a body with If-Match and bumps the version as the device", async () => {
    const body = { ...GOAL_SETTINGS, targets: { ...GOAL_SETTINGS.targets, steps: 11000 } };
    const { status, body: result } = await call("/v1/documents/goalSettings", {
      method: "PUT",
      headers: { "If-Match": "1" },
      body: JSON.stringify(body),
    });
    expect(status).toBe(200);
    expect(result.document).toMatchObject({ version: 2, updatedBy: "device" });
    expect(result.document.targets.steps).toBe(11000);
  });

  it("answers 409 with the document as it now stands, so the phone can merge", async () => {
    await write("set_targets", { kcal: 2000 });
    const { status, body } = await call("/v1/documents/goalSettings", {
      method: "PUT",
      headers: { "If-Match": "1" },
      body: JSON.stringify(GOAL_SETTINGS),
    });
    expect(status).toBe(409);
    expect(body.error).toBe("version_conflict");
    expect(body).toMatchObject({ expected: 1, currentVersion: 2 });
    expect(body.document).toMatchObject({ version: 2, updatedBy: "muse" });
    expect(body.document.targets.kcal).toBe(2000);
  });

  it("requires If-Match rather than guessing", async () => {
    const { status, body } = await call("/v1/documents/goalSettings", {
      method: "PUT",
      body: JSON.stringify(GOAL_SETTINGS),
    });
    expect(status).toBe(428);
    expect(body.error).toBe("precondition_required");
  });

  it("holds the device to the same §2 invariants as Muse", async () => {
    const { status, body } = await call("/v1/documents/goalSettings", {
      method: "PUT",
      headers: { "If-Match": "1" },
      body: JSON.stringify({
        ...GOAL_SETTINGS,
        targets: { ...GOAL_SETTINGS.targets, fatMinG: 40 },
      }),
    });
    expect(status).toBe(422);
    expect(body.error).toBe("invariant_violation");
    expect(body.issues).toMatchObject([{ path: "targets.fatMinG" }]);
  });

  it("holds the device to §F5 too", async () => {
    const illegal = programWith([
      { weekday: 1, kind: "upperA" },
      { weekday: 2, kind: "upperB" },
      { weekday: 3, kind: "rest" },
      { weekday: 4, kind: "lowerA" },
      { weekday: 5, kind: "rest" },
      { weekday: 6, kind: "lowerB" },
      { weekday: 7, kind: "rest" },
    ]);
    const { status, body } = await call("/v1/documents/program", {
      method: "PUT",
      headers: { "If-Match": "1" },
      body: JSON.stringify(illegal),
    });
    expect(status).toBe(422);
    expect(body.issues[0].message).toContain("less than 48 h apart");
  });

  it("rejects a body that carries the envelope keys", async () => {
    const { status, body } = await call("/v1/documents/flags", {
      method: "PUT",
      headers: { "If-Match": "1" },
      body: JSON.stringify({
        remoteBridgeEnabled: true,
        museWritesEnabled: true,
        museWriteMode: "apply",
        rawDetailSyncEnabled: false,
        foundationModelsEnabled: true,
        version: 1,
      }),
    });
    expect(status).toBe(400);
    expect(body.error).toBe("contract_violation");
  });

  it("writes the program the device owns, with If-Match 0 when it has none", async () => {
    await seedDocuments({ program: null });
    const { status, body } = await call("/v1/documents/program", {
      method: "PUT",
      headers: { "If-Match": "0" },
      body: JSON.stringify(PROGRAM),
    });
    expect(status).toBe(200);
    expect(body.document).toMatchObject({ version: 1, name: "Upper/Lower 4-day" });
    // A document write is not a mutation: the log is Muse's instructions to the
    // phone, and a phone edit replayed to the phone would be a loop.
    expect(await mutationRows()).toHaveLength(0);
  });

  it("needs the device token", async () => {
    expect((await call("/v1/documents/flags", { token: null })).status).toBe(401);
  });
});

describe("POST /v1/device/push-token", () => {
  beforeEach(async () => {
    await seedDocuments();
    await testEnv.DB.prepare(`DELETE FROM push_tokens`).run();
  });

  const token = "a".repeat(64);

  it("registers a token, and replaces the device's previous one", async () => {
    const first = await call("/v1/device/push-token", {
      method: "POST",
      body: JSON.stringify({ token, deviceId: "device-1", environment: "sandbox" }),
    });
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({ registered: 1, environment: "sandbox" });

    const rotated = await call("/v1/device/push-token", {
      method: "POST",
      body: JSON.stringify({ token: "b".repeat(64), deviceId: "device-1" }),
    });
    expect(rotated.body.registered).toBe(1);
    const { results } = await testEnv.DB.prepare(`SELECT token FROM push_tokens`).all<{
      token: string;
    }>();
    expect(results.map((row) => row.token)).toEqual(["b".repeat(64)]);
  });

  it("rejects a token that is not lowercase hex", async () => {
    const { status, body } = await call("/v1/device/push-token", {
      method: "POST",
      body: JSON.stringify({ token: "NOT-HEX", deviceId: "device-1" }),
    });
    expect(status).toBe(400);
    expect(body.error).toBe("contract_violation");
  });

  it("needs the device token", async () => {
    expect(
      (
        await call("/v1/device/push-token", {
          method: "POST",
          token: null,
          body: JSON.stringify({ token, deviceId: "device-1" }),
        })
      ).status,
    ).toBe(401);
  });
});

describe("GET|POST /v1/suggestions", () => {
  beforeEach(async () => {
    await seedDocuments({ flags: { museWriteMode: "propose" } });
  });

  it("lists what is waiting for a one-tap accept", async () => {
    const proposed = await write("set_targets", { kcal: 2000 });
    const { status, body } = await call("/v1/suggestions?status=pending");
    expect(status).toBe(200);
    expect(body.suggestions).toMatchObject([
      {
        id: proposed.suggestionId,
        source: "muse",
        kind: "set_targets",
        status: "pending",
        action: { kind: "set_targets", payload: { kcal: 2000 } },
      },
    ]);
  });

  it("takes the phone's own suggestions, so accept_suggestion can action them", async () => {
    const { status, body } = await call("/v1/suggestions", {
      method: "POST",
      body: JSON.stringify({
        schemaVersion: 1,
        suggestions: [
          {
            id: "sug_weekly_1",
            createdAt: "2026-11-03T08:00:00-05:00",
            kind: "calorieAdjust",
            text: "Down 0.6 kg a week — hold calories at 2,050",
            action: { kind: "set_targets", payload: { kcal: 2050 } },
          },
        ],
      }),
    });
    expect(status).toBe(200);
    expect(body.accepted).toBe(1);
    expect(body.suggestions[0]).toMatchObject({ source: "device", status: "pending" });

    const accepted = await write("accept_suggestion", { suggestionId: "sug_weekly_1" });
    expect(accepted.status).toBe("applied");
    const { body: after } = await call("/v1/suggestions?status=accepted");
    expect(after.suggestions).toHaveLength(1);
  });

  it("rejects an unknown status filter and a malformed upload", async () => {
    expect((await call("/v1/suggestions?status=maybe")).status).toBe(400);
    expect(
      (
        await call("/v1/suggestions", {
          method: "POST",
          body: JSON.stringify({ suggestions: [{ id: "x" }] }),
        })
      ).status,
    ).toBe(400);
  });

  it("needs the device token", async () => {
    expect((await call("/v1/suggestions", { token: null })).status).toBe(401);
  });
});

describe("the status page", () => {
  it("names the Stream B endpoints and leaks no secret", async () => {
    const { status, body } = await call("/", { token: null });
    expect(status).toBe(200);
    expect(body).toMatchObject({ mutations: "/v1/mutations", documents: "/v1/documents/<key>" });
    expect(JSON.stringify(body)).not.toContain(TOKEN);
  });
});
