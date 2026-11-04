import { describe, expect, it } from "vitest";
import { DayRollup, IngestEnvelope, SCHEMA_VERSION } from "../src/contract";
import documentedExample from "./export-schema-example.json" with { type: "json" };

describe("the data contract", () => {
  it("parses the DayRollup printed in docs/EXPORT_SCHEMA.md §1 verbatim", () => {
    const parsed = DayRollup.safeParse(documentedExample);
    expect(parsed.success, JSON.stringify(parsed.error?.issues)).toBe(true);
  });

  it("pins schemaVersion at 1", () => {
    expect(SCHEMA_VERSION).toBe(1);
  });

  it("rejects an unknown sessionPlanned rather than coercing it", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    rollup.training.sessionPlanned = "upperC";
    const parsed = DayRollup.safeParse(rollup);
    expect(parsed.success).toBe(false);
    expect(parsed.error?.issues[0]?.path.join(".")).toBe("training.sessionPlanned");
  });

  it("rejects an unknown readiness verdict", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    rollup.readiness.verdict = "deload";
    expect(DayRollup.safeParse(rollup).success).toBe(false);
  });

  it("rejects an unknown soreness level", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    rollup.checkIn.soreness.quads = "agony";
    expect(DayRollup.safeParse(rollup).success).toBe(false);
  });

  it("rejects an extra field, because that means the app has diverged", () => {
    const rollup = structuredClone(documentedExample) as Record<string, unknown>;
    rollup.mood = 7;
    const parsed = DayRollup.safeParse(rollup);
    expect(parsed.success).toBe(false);
    expect(JSON.stringify(parsed.error?.issues)).toContain("mood");
  });

  it("rejects a missing soreness group", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    delete rollup.checkIn.soreness.core;
    expect(DayRollup.safeParse(rollup).success).toBe(false);
  });

  it("rejects energy outside 1..5 and wins.total outside 0..4", () => {
    const energy = structuredClone(documentedExample) as Record<string, any>;
    energy.checkIn.energy = 6;
    expect(DayRollup.safeParse(energy).success).toBe(false);

    const wins = structuredClone(documentedExample) as Record<string, any>;
    wins.wins.total = 5;
    expect(DayRollup.safeParse(wins).success).toBe(false);
  });

  it("accepts null for a measurement that was not taken", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    rollup.vitals.hrvSdnnMs = null;
    rollup.body.weightKg = null;
    expect(DayRollup.safeParse(rollup).success).toBe(true);
  });

  it("requires a timestamp to carry an offset", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    rollup.updatedAt = "2026-11-03T23:05:00";
    expect(DayRollup.safeParse(rollup).success).toBe(false);
  });

  it("accepts a null checkIn and readiness on a day with neither", () => {
    const rollup = structuredClone(documentedExample) as Record<string, any>;
    rollup.checkIn = null;
    rollup.readiness = null;
    expect(DayRollup.safeParse(rollup).success).toBe(true);
  });

  it("takes an ingest envelope with an explicit schemaVersion", () => {
    expect(
      IngestEnvelope.safeParse({ schemaVersion: 1, rollups: [documentedExample] })
        .success,
    ).toBe(true);
    expect(
      IngestEnvelope.safeParse({ schemaVersion: 2, rollups: [documentedExample] })
        .success,
    ).toBe(false);
  });
});
