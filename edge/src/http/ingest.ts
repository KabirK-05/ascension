import { z } from "zod";
import { IngestEnvelope } from "../contract";
import { upsertRollups } from "../db/rollups";
import type { Env } from "../env";
import { bearerMatches, json, problem } from "./respond";

/**
 * Rolling retention is 400 days (docs/TECH_STACK.md §2.6), so a batch larger
 * than that is a bug on the phone, not a backfill.
 */
const MAX_BATCH = 400;

/** Enough to fix the divergence, few enough that a bad batch cannot flood logs. */
const MAX_REPORTED_ISSUES = 20;

function issues(error: z.ZodError): Array<{ path: string; message: string }> {
  return error.issues.slice(0, MAX_REPORTED_ISSUES).map((issue) => ({
    path: issue.path.join("."),
    message: issue.message,
  }));
}

/**
 * `POST /v1/ingest` — Stream A. Accepts a batch of `DayRollup` objects and
 * upserts on `date`.
 *
 * The whole batch is rejected if any rollup fails validation: a half-applied
 * batch would leave the phone unable to tell what landed, and an unknown enum
 * value or an extra field means the app and this contract have diverged, which
 * must be loud rather than coerced.
 */
export async function handleIngest(
  request: Request,
  env: Env,
): Promise<Response> {
  if (request.method !== "POST") {
    return problem(405, "method_not_allowed", { allow: "POST" });
  }
  if (!(await bearerMatches(request.headers.get("Authorization"), env.DEVICE_TOKEN))) {
    return problem(401, "unauthorized", {
      hint: "present the device token as `Authorization: Bearer <token>`",
    });
  }

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return problem(400, "invalid_json");
  }

  const envelope = Array.isArray(raw) ? { rollups: raw } : raw;
  const parsed = IngestEnvelope.safeParse(envelope);
  if (!parsed.success) {
    return problem(400, "contract_violation", {
      hint: "field names and enums must match docs/EXPORT_SCHEMA.md exactly",
      issues: issues(parsed.error),
    });
  }

  const { rollups } = parsed.data;
  if (rollups.length > MAX_BATCH) {
    return problem(413, "batch_too_large", {
      limit: MAX_BATCH,
      received: rollups.length,
    });
  }

  const duplicates = [
    ...new Set(
      rollups
        .map((rollup) => rollup.date)
        .filter((date, index, all) => all.indexOf(date) !== index),
    ),
  ];
  if (duplicates.length > 0) {
    return problem(400, "duplicate_dates", { dates: duplicates });
  }

  const ingestedAt = new Date().toISOString();
  await upsertRollups(env.DB, rollups, ingestedAt);

  return json({
    accepted: rollups.length,
    dates: rollups.map((rollup) => rollup.date).sort(),
    ingestedAt,
  });
}
