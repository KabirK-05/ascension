/**
 * `POST /v1/device/push-token` — where the phone registers for the silent wake.
 *
 * `RemoteNotificationRegistrar` deliberately does not invent a path to post to:
 * the endpoint is the Worker's to define, and this is it. APNs rotates tokens,
 * so this is an upsert, and the row holds an APNs token, a random `deviceId` and
 * a timestamp — no name, no email, nothing that identifies a person
 * (docs/TECH_STACK.md §2.6).
 */
import { z } from "zod";
import { isoTimestamp } from "../contract";
import type { Env } from "../env";
import { zodIssues } from "../mcp/errors";
import { json, problem, requireDeviceToken } from "./respond";

const Registration = z.strictObject({
  schemaVersion: z.number().int().optional(),
  /** Lowercase hex, as `RemoteNotificationRegistrar.hex` formats it. */
  token: z
    .string()
    .regex(/^[0-9a-f]{32,200}$/, "an APNs token is lowercase hex, 32-200 characters"),
  /** The random UUID the app generates on first launch. */
  deviceId: z.string().min(1).max(64),
  environment: z.enum(["production", "sandbox"]).optional(),
  updatedAt: isoTimestamp.optional(),
});

export async function handlePushToken(request: Request, env: Env): Promise<Response> {
  const unauthorized = await requireDeviceToken(request, env.DEVICE_TOKEN);
  if (unauthorized) return unauthorized;

  if (request.method !== "POST") {
    return problem(405, "method_not_allowed", { allow: "POST" });
  }

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return problem(400, "invalid_json");
  }

  const parsed = Registration.safeParse(raw);
  if (!parsed.success) {
    return problem(400, "contract_violation", { issues: zodIssues(parsed.error) });
  }

  const { token, deviceId } = parsed.data;
  const environment = parsed.data.environment ?? "production";
  const updatedAt = parsed.data.updatedAt ?? new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO push_tokens (token, deviceId, environment, updatedAt)
     VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT(token) DO UPDATE SET
       deviceId    = excluded.deviceId,
       environment = excluded.environment,
       updatedAt   = excluded.updatedAt`,
  )
    .bind(token, deviceId, environment, updatedAt)
    .run();

  // A rotated token leaves the old row behind, and pushing to it would be a
  // wasted call for the life of the install: one device, one row.
  await env.DB.prepare(
    `DELETE FROM push_tokens WHERE deviceId = ?1 AND token != ?2`,
  )
    .bind(deviceId, token)
    .run();

  const { registered } = (await env.DB.prepare(
    `SELECT count(*) AS registered FROM push_tokens`,
  ).first<{ registered: number }>()) ?? { registered: 0 };

  return json({ registered, environment, updatedAt });
}
