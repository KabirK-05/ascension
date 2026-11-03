import { SELF } from "cloudflare:test";
import { testEnv } from "./env";
import { beforeEach, describe, expect, it } from "vitest";
import { DOCUMENTED_EXAMPLE, makeRollup } from "./fixtures";

const INGEST = "http://localhost:8787/v1/ingest";

async function post(
  body: unknown,
  token: string | null = testEnv.DEVICE_TOKEN,
): Promise<Response> {
  return SELF.fetch(INGEST, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

async function rowCount(): Promise<number> {
  const row = await testEnv.DB.prepare(`SELECT count(*) AS n FROM rollups`).first<{
    n: number;
  }>();
  return row?.n ?? 0;
}

describe("POST /v1/ingest", () => {
  beforeEach(async () => {
    await testEnv.DB.prepare(`DELETE FROM rollups`).run();
  });

  it("accepts a batch and stores it", async () => {
    const response = await post({
      rollups: [makeRollup("2026-11-01", 1), makeRollup("2026-11-02", 2)],
    });
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      schemaVersion: 1,
      accepted: 2,
      dates: ["2026-11-01", "2026-11-02"],
    });
    expect(await rowCount()).toBe(2);
  });

  it("accepts a bare array as well as the envelope", async () => {
    const response = await post([DOCUMENTED_EXAMPLE]);
    expect(response.status).toBe(200);
    expect(await rowCount()).toBe(1);
  });

  it("upserts on date, so re-sending a day is idempotent", async () => {
    const first = makeRollup("2026-11-02", 2);
    expect((await post({ rollups: [first] })).status).toBe(200);
    expect((await post({ rollups: [first] })).status).toBe(200);
    expect((await post({ rollups: [first] })).status).toBe(200);
    expect(await rowCount()).toBe(1);

    const stored = await testEnv.DB.prepare(
      `SELECT json FROM rollups WHERE date = '2026-11-02'`,
    ).first<{ json: string }>();
    expect(JSON.parse(stored!.json)).toEqual(first);
  });

  it("lets a re-sent day correct itself", async () => {
    const original = makeRollup("2026-11-02", 2);
    await post({ rollups: [original] });

    const corrected = structuredClone(original);
    corrected.nutrition.proteinG = 162;
    corrected.updatedAt = "2026-11-03T08:00:00-05:00";
    await post({ rollups: [corrected] });

    expect(await rowCount()).toBe(1);
    const row = await testEnv.DB.prepare(
      `SELECT json, updatedAt FROM rollups WHERE date = '2026-11-02'`,
    ).first<{ json: string; updatedAt: string }>();
    expect(JSON.parse(row!.json).nutrition.proteinG).toBe(162);
    expect(row!.updatedAt).toBe("2026-11-03T08:00:00-05:00");
  });

  it("refuses without the device token", async () => {
    expect((await post({ rollups: [] }, null)).status).toBe(401);
    expect((await post({ rollups: [] }, "wrong-token")).status).toBe(401);
    expect(await rowCount()).toBe(0);
  });

  it("rejects the whole batch when one rollup breaks the contract", async () => {
    const good = makeRollup("2026-11-01", 1);
    const bad = structuredClone(makeRollup("2026-11-02", 2)) as Record<string, any>;
    bad.training.sessionPlanned = "upperC";

    const response = await post({ rollups: [good, bad] });
    expect(response.status).toBe(400);
    const body = (await response.json()) as Record<string, any>;
    expect(body.error).toBe("contract_violation");
    expect(body.issues[0].path).toBe("rollups.1.training.sessionPlanned");
    // Atomic: the good rollup must not have landed either.
    expect(await rowCount()).toBe(0);
  });

  it("rejects an unknown field loudly", async () => {
    const rollup = structuredClone(makeRollup("2026-11-01", 1)) as Record<string, unknown>;
    rollup.mood = 7;
    const response = await post({ rollups: [rollup] });
    expect(response.status).toBe(400);
    expect(JSON.stringify(await response.json())).toContain("mood");
  });

  it("rejects two copies of the same date in one batch", async () => {
    const response = await post({
      rollups: [makeRollup("2026-11-02", 2), makeRollup("2026-11-02", 3)],
    });
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({
      error: "duplicate_dates",
      dates: ["2026-11-02"],
    });
  });

  it("rejects malformed JSON and the wrong method", async () => {
    const malformed = await SELF.fetch(INGEST, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${testEnv.DEVICE_TOKEN}`,
      },
      body: "{not json",
    });
    expect(malformed.status).toBe(400);

    const wrongMethod = await SELF.fetch(INGEST, { method: "GET" });
    expect(wrongMethod.status).toBe(405);
  });

  it("takes an empty batch as a no-op", async () => {
    const response = await post({ rollups: [] });
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ accepted: 0 });
  });
});
