/**
 * `GET /v1/mutations?since=<cursor>` and `POST /v1/mutations/ack` — how the
 * phone drains Muse's write log (docs/TECH_STACK.md §2.3).
 *
 * The page is not filtered on `appliedAt`: the device applies Tier-1 mutations
 * too, to catch its local copy up with a write the Worker already made, so the
 * cursor alone decides the page. Ids are ULIDs, so `WHERE id > ?` is both the
 * cursor and the order they must be applied in.
 */
import { MutationAck } from "../contract";
import { ackMutations, countPending, listMutationsSince } from "../db/mutations";
import type { Env } from "../env";
import { zodIssues } from "../mcp/errors";
import { isUlid } from "../ulid";
import { json, problem, requireDeviceToken } from "./respond";

/** One page. Large enough that a fresh install drains in one or two round trips. */
const PAGE_SIZE = 500;

export async function handleMutations(request: Request, env: Env): Promise<Response> {
  const unauthorized = await requireDeviceToken(request, env.DEVICE_TOKEN);
  if (unauthorized) return unauthorized;

  if (request.method !== "GET") {
    return problem(405, "method_not_allowed", { allow: "GET" });
  }

  const since = new URL(request.url).searchParams.get("since");
  if (since !== null && since !== "" && !isUlid(since)) {
    return problem(400, "invalid_cursor", {
      since,
      hint: "`since` is the last mutation id you applied: 26 Crockford base32 characters",
    });
  }

  const page = await listMutationsSince(env.DB, since || null, PAGE_SIZE);
  return json({
    mutations: page.mutations,
    cursor: page.cursor,
    pending: await countPending(env.DB),
    ...(page.unreadableIds.length > 0 ? { unreadableIds: page.unreadableIds } : {}),
  });
}

/**
 * The ack stamps `appliedAt` from the *device's* instant, so a drain that
 * happened offline keeps the time it really happened — and only where it is
 * NULL, so a re-delivered page cannot move a timestamp already recorded.
 */
export async function handleMutationAck(request: Request, env: Env): Promise<Response> {
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

  const parsed = MutationAck.safeParse(raw);
  if (!parsed.success) {
    return problem(400, "contract_violation", {
      hint: "`{ ids: [ULID], appliedAt: ISO-8601 }`",
      issues: zodIssues(parsed.error),
    });
  }

  const outcome = await ackMutations(env.DB, parsed.data.ids, parsed.data.appliedAt);
  return json({
    acked: outcome.acked,
    alreadyApplied: outcome.alreadyApplied,
    unknown: outcome.unknown,
    pending: await countPending(env.DB),
  });
}
