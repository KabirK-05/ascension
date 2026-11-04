/**
 * Open suggestions: the §F6 calorie auto-adjust the phone raised, and the Tier-1
 * writes Muse asked for while `flags.museWriteMode` was `propose`.
 *
 * Decided rows are kept, never deleted — there are no delete tools in v1, and
 * what was accepted and when is part of the audit trail.
 */
import { Suggestion, type MutationKind } from "../contract";

type Row = {
  id: string;
  createdAt: string;
  source: string;
  kind: string;
  text: string;
  actionKind: string | null;
  actionPayload: string | null;
  status: string;
  decidedAt: string | null;
};

export type SuggestionAction = { kind: MutationKind; payload: unknown };

function decode(row: Row): Suggestion | null {
  const parsed = Suggestion.safeParse({
    id: row.id,
    createdAt: row.createdAt,
    source: row.source,
    kind: row.kind,
    text: row.text,
    action:
      row.actionKind === null || row.actionPayload === null
        ? null
        : { kind: row.actionKind, payload: JSON.parse(row.actionPayload) },
    status: row.status,
    decidedAt: row.decidedAt,
  });
  return parsed.success ? parsed.data : null;
}

const COLUMNS = `id, createdAt, source, kind, text, actionKind, actionPayload, status, decidedAt`;

export async function recordSuggestion(
  db: D1Database,
  suggestion: {
    id: string;
    createdAt: string;
    source: "muse" | "device";
    kind: string;
    text: string;
    action: SuggestionAction | null;
  },
): Promise<Suggestion> {
  await db
    .prepare(
      `INSERT INTO suggestions (${COLUMNS})
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'pending', NULL)
       ON CONFLICT(id) DO UPDATE SET
         createdAt     = excluded.createdAt,
         source        = excluded.source,
         kind          = excluded.kind,
         text          = excluded.text,
         actionKind    = excluded.actionKind,
         actionPayload = excluded.actionPayload
       WHERE suggestions.status = 'pending'`,
    )
    .bind(
      suggestion.id,
      suggestion.createdAt,
      suggestion.source,
      suggestion.kind,
      suggestion.text,
      suggestion.action?.kind ?? null,
      suggestion.action ? JSON.stringify(suggestion.action.payload) : null,
    )
    .run();
  const stored = await getSuggestion(db, suggestion.id);
  if (!stored) throw new Error(`recorded suggestion ${suggestion.id} but could not read it back`);
  return stored;
}

export async function getSuggestion(
  db: D1Database,
  id: string,
): Promise<Suggestion | null> {
  const row = await db
    .prepare(`SELECT ${COLUMNS} FROM suggestions WHERE id = ?1`)
    .bind(id)
    .first<Row>();
  return row ? decode(row) : null;
}

export async function listSuggestions(
  db: D1Database,
  options: { status?: "pending" | "accepted"; limit?: number } = {},
): Promise<Suggestion[]> {
  const limit = options.limit ?? 100;
  const { results } = options.status
    ? await db
        .prepare(
          `SELECT ${COLUMNS} FROM suggestions WHERE status = ?1
           ORDER BY createdAt ASC, id ASC LIMIT ?2`,
        )
        .bind(options.status, limit)
        .all<Row>()
    : await db
        .prepare(
          `SELECT ${COLUMNS} FROM suggestions ORDER BY createdAt ASC, id ASC LIMIT ?1`,
        )
        .bind(limit)
        .all<Row>();
  return results.map(decode).filter((item): item is Suggestion => item !== null);
}

/**
 * Mark a suggestion accepted, once. Returns `false` when it had already been
 * decided, so a second `accept_suggestion` cannot apply the same change twice.
 */
export async function markAccepted(
  db: D1Database,
  id: string,
  decidedAt: string,
): Promise<boolean> {
  const result = await db
    .prepare(
      `UPDATE suggestions SET status = 'accepted', decidedAt = ?2
       WHERE id = ?1 AND status = 'pending'`,
    )
    .bind(id, decidedAt)
    .run();
  return (result.meta.changes ?? 0) > 0;
}
