import { SCHEMA_VERSION } from "../contract";

/** Every response carries `schemaVersion` (docs/TECH_STACK.md §2.5). */
export function json(
  body: Record<string, unknown>,
  init: ResponseInit = {},
): Response {
  return Response.json({ schemaVersion: SCHEMA_VERSION, ...body }, init);
}

export function problem(
  status: number,
  error: string,
  detail?: Record<string, unknown>,
): Response {
  return json({ error, ...detail }, { status });
}

/**
 * Constant-time secret comparison. Both sides are hashed first, so the
 * comparison is over equal-length digests and the secret's length does not leak.
 */
export async function secretMatches(
  presented: string | null | undefined,
  expected: string | undefined,
): Promise<boolean> {
  if (!presented || !expected) return false;
  const digest = async (value: string) =>
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return crypto.subtle.timingSafeEqual(
    await digest(presented),
    await digest(expected),
  );
}

export async function bearerMatches(
  header: string | null,
  expected: string | undefined,
): Promise<boolean> {
  return secretMatches(/^Bearer (.+)$/.exec(header ?? "")?.[1], expected);
}

/**
 * Stream B's device half, like `POST /v1/ingest`, authenticates with the device
 * token in the phone's Keychain, never with an OAuth grant
 * (docs/TECH_STACK.md §2.6). Returns the 401 to send, or `null` when the token
 * is good.
 */
export async function requireDeviceToken(
  request: Request,
  expected: string | undefined,
): Promise<Response | null> {
  if (await bearerMatches(request.headers.get("Authorization"), expected)) {
    return null;
  }
  return problem(401, "unauthorized", {
    hint: "present the device token as `Authorization: Bearer <token>`",
  });
}
