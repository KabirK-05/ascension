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
