/**
 * `GET|PUT /v1/documents/<key>` — Stream B's phone-side half
 * (docs/TECH_STACK.md §2.3).
 *
 * The phone edits the same three documents Muse does, so it goes through the
 * same gate: `If-Match: <version>`, and the §2 invariants. A rule the Worker
 * enforced for Muse and waived for the device would let the phone store a
 * document Muse could never write, and the next Muse write would fail on a
 * document it did not break.
 *
 * On `409` the body carries the document as it now stands, which is what lets
 * the phone merge last-write-wins per field and retry (`DocumentClient`).
 */
import { documentBodies, DocumentKey } from "../contract";
import { readDocument, writeDocument } from "../db/documents";
import type { Env } from "../env";
import { checkGoalSettings, checkProgram } from "../guardrails";
import { zodIssues } from "../mcp/errors";
import { json, problem, requireDeviceToken } from "./respond";

/** The invariant check for a key, or none for a document that has no invariants. */
function invariantsFor(key: DocumentKey) {
  if (key === "goalSettings") return checkGoalSettings;
  if (key === "program") return checkProgram;
  return null;
}

export async function handleDocument(
  request: Request,
  env: Env,
  rawKey: string,
): Promise<Response> {
  const unauthorized = await requireDeviceToken(request, env.DEVICE_TOKEN);
  if (unauthorized) return unauthorized;

  const key = DocumentKey.safeParse(rawKey);
  if (!key.success) {
    return problem(404, "unknown_document", { key: rawKey, known: DocumentKey.options });
  }

  if (request.method === "GET") {
    const document = await readDocument(env.DB, key.data);
    if (!document) return problem(404, "not_found", { key: key.data });
    return json({ document: { key: key.data, ...document } });
  }

  if (request.method !== "PUT") {
    return problem(405, "method_not_allowed", { allow: "GET, PUT" });
  }

  const ifMatch = request.headers.get("If-Match");
  if (ifMatch === null) {
    return problem(428, "precondition_required", {
      hint: "send `If-Match: <version>`; 0 writes a document that does not exist yet",
    });
  }
  const expectedVersion = Number(ifMatch);
  if (!Number.isInteger(expectedVersion) || expectedVersion < 0) {
    return problem(400, "invalid_if_match", { ifMatch });
  }

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return problem(400, "invalid_json");
  }

  const parsed = documentBodies[key.data].safeParse(raw);
  if (!parsed.success) {
    return problem(400, "contract_violation", {
      hint: "a document body carries no version/updatedAt/updatedBy — those are columns",
      issues: zodIssues(parsed.error),
    });
  }

  const invariants = invariantsFor(key.data);
  const issues = invariants ? invariants(parsed.data as never) : [];
  if (issues.length > 0) {
    return problem(422, "invariant_violation", { document: key.data, issues });
  }

  const outcome = await writeDocument(env.DB, key.data, parsed.data, {
    expectedVersion,
    updatedBy: "device",
    updatedAt: new Date().toISOString(),
  });
  if (!outcome.ok) {
    return problem(409, "version_conflict", {
      expected: expectedVersion,
      currentVersion: outcome.currentVersion,
      document: outcome.document ? { key: key.data, ...outcome.document } : null,
    });
  }

  return json({ document: { key: key.data, ...outcome.document } });
}
