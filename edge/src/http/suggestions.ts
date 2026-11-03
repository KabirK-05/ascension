/**
 * `GET|POST /v1/suggestions` — the open suggestions, both halves of them.
 *
 * `GET` is what Today's one-tap accept list reads: the §F6 calorie auto-adjusts
 * the phone raised, and the Tier-1 writes Muse proposed while
 * `flags.museWriteMode` was `propose`.
 *
 * `POST` is the phone handing its own suggestions up, so `accept_suggestion` can
 * action them on the owner's behalf — the capability doc's headline use of that
 * tool. A suggestion the phone can apply but the cloud cannot carries no
 * `action`; accepting it then queues a mutation instead of writing a document.
 *
 * Nothing is deleted here. A decided suggestion keeps its row: there are no
 * delete tools in v1, and what was accepted and when is part of the audit trail.
 */
import { SuggestionUpload } from "../contract";
import { listSuggestions, recordSuggestion } from "../db/suggestions";
import type { Env } from "../env";
import { zodIssues } from "../mcp/errors";
import { json, problem, requireDeviceToken } from "./respond";

export async function handleSuggestions(request: Request, env: Env): Promise<Response> {
  const unauthorized = await requireDeviceToken(request, env.DEVICE_TOKEN);
  if (unauthorized) return unauthorized;

  if (request.method === "GET") {
    const status = new URL(request.url).searchParams.get("status");
    if (status !== null && status !== "pending" && status !== "accepted") {
      return problem(400, "invalid_status", { status, known: ["pending", "accepted"] });
    }
    return json({
      suggestions: await listSuggestions(env.DB, status ? { status } : {}),
    });
  }

  if (request.method !== "POST") {
    return problem(405, "method_not_allowed", { allow: "GET, POST" });
  }

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return problem(400, "invalid_json");
  }

  const parsed = SuggestionUpload.safeParse(raw);
  if (!parsed.success) {
    return problem(400, "contract_violation", { issues: zodIssues(parsed.error) });
  }

  const stored = [];
  for (const suggestion of parsed.data.suggestions) {
    stored.push(
      await recordSuggestion(env.DB, {
        id: suggestion.id,
        createdAt: suggestion.createdAt,
        source: "device",
        kind: suggestion.kind,
        text: suggestion.text,
        action: suggestion.action ?? null,
      }),
    );
  }
  return json({ accepted: stored.length, suggestions: stored });
}
