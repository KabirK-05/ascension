/**
 * Tier 1 and Tier 2 — the write tools (docs/MUSE_CAPABILITIES.md).
 *
 * The point of the whole bridge: Muse manages this app exactly as its owner
 * can. So these write with full authority and no confirmation, and the Worker is
 * the only thing standing between a bad tool call and a bad training week —
 * every invariant in `guardrails.ts` is enforced here, server-side, and a write
 * that breaks one is rejected rather than coerced into legality.
 *
 * Two tiers, and the difference is where the state lives:
 *
 *   Tier 1  `documents` in D1. The Worker applies it, and it is live the moment
 *           the app next reads. `set_staples` and `accept_suggestion` are Tier 1
 *           in the log but have no cloud-side document -- the staples list and
 *           the suggestion ledger are the phone's -- so they queue like Tier 2
 *           and answer `pending_device_apply`, which is the honest answer.
 *
 *   Tier 2  an API only the device has. The tool appends a mutation and answers
 *           `pending_device_apply`: an assistant may never report a HealthKit
 *           write as landed before the phone has applied it.
 *
 * There are no delete tools, in either tier (docs/MUSE_CAPABILITIES.md).
 */
import { z } from "zod";
import {
  type DocumentKey,
  FlagsBody,
  type FlagsBody as Flags,
  GoalSettingsBody,
  isoDate,
  LogCheckInPayload,
  LogMealPayload,
  LogTopSetPayload,
  LogWaterPayload,
  type MutationKind,
  ProgramBody,
  ScheduleWorkoutPayload,
  SessionKind,
  StaplesPayload,
  TargetsPatch,
  tierOf,
  TriggerExportPayload,
  type WriteStatus,
} from "../contract";
import {
  documentVersion,
  readFlags,
  readGoalSettings,
  readProgram,
  writeDocument,
  type StoredDocument,
} from "../db/documents";
import { appendMutation, countPending } from "../db/mutations";
import {
  getSuggestion,
  listSuggestions,
  markAccepted,
  recordSuggestion,
} from "../db/suggestions";
import type { PushResult } from "../push/apns";
import { ulid } from "../ulid";
import { checkGoalSettings, checkProgram, type Issue } from "../guardrails";
import { parseArgs, ToolError } from "./errors";

export type WriteContext = {
  db: D1Database;
  /**
   * Wake the phone after queueing. Injected rather than imported so a Worker
   * with no APNs key -- `wrangler dev`, the tests -- queues exactly the same way.
   */
  wake?: () => Promise<PushResult>;
  /** The Worker's clock, injectable for tests. */
  now?: () => string;
};

export type WriteTool = {
  name: string;
  title: string;
  description: string;
  tier: 1 | 2;
  inputSchema: z.ZodObject<z.ZodRawShape>;
  run(args: unknown, ctx: WriteContext): Promise<Record<string, unknown>>;
};

function defineWrite<Shape extends z.ZodRawShape>(tool: {
  name: MutationKind;
  title: string;
  description: string;
  inputSchema: z.ZodObject<Shape>;
  run(args: unknown, ctx: WriteContext): Promise<Record<string, unknown>>;
}): WriteTool {
  return { ...tool, tier: tierOf(tool.name) };
}

const nowOf = (ctx: WriteContext) => (ctx.now ?? (() => new Date().toISOString()))();

/** `If-Match`, as a tool argument. `0` means "the document does not exist yet". */
const ifMatchArg = {
  ifMatch: z
    .number()
    .int()
    .min(0)
    .optional()
    .describe(
      "The document version this edit was made against; the write is rejected if it has moved since. Omit to write whatever is current.",
    ),
};

/* ------------------------------------------------------------------- flags -- */

type WriteMode = Flags["museWriteMode"];

/**
 * The two flags that gate every write (docs/TECH_STACK.md §2.7, §2.1 of the
 * capabilities doc). Unreadable flags refuse the write: fail safe, since the
 * document that says whether Muse may write is the one thing that cannot be
 * assumed.
 */
async function writeGate(ctx: WriteContext): Promise<{ mode: WriteMode }> {
  const flags = await readFlags(ctx.db);
  if (!flags) {
    throw new ToolError(
      "flags_unreadable",
      "the `flags` document is missing or does not match the contract, so writes are refused",
      { document: "flags" },
    );
  }
  if (!flags.museWritesEnabled) {
    throw new ToolError(
      "writes_disabled",
      "`flags.museWritesEnabled` is off, so this server is read-only right now",
      { hint: "turn Muse writes back on in the app; the flag is not writable while it is off" },
    );
  }
  return { mode: flags.museWriteMode };
}

/* ------------------------------------------------------- prepare and commit -- */

type Change = { field: string; from: unknown; to: unknown };

/** A validated Tier-1 document write, ready to apply or to propose. */
type Prepared = {
  key: DocumentKey;
  kind: MutationKind;
  /** The whole next body, which is what the `documents` row stores. */
  body: unknown;
  /** The mutation payload §3 declares for this kind. */
  payload: unknown;
  currentVersion: number;
  changed: Change[];
  summary: string;
};

function reject(issues: Issue[], document: DocumentKey): never {
  throw new ToolError(
    "invariant_violation",
    `the write breaks the ${document} invariants docs/EXPORT_SCHEMA.md §2 declares`,
    { document, issues },
  );
}

async function requireDocument<Body>(
  ctx: WriteContext,
  key: DocumentKey,
  read: (db: D1Database) => Promise<StoredDocument<Body> | null>,
): Promise<StoredDocument<Body>> {
  const document = await read(ctx.db);
  if (!document) {
    throw new ToolError(
      "missing_document",
      `the \`${key}\` document is missing or does not match the contract`,
      { document: key, hint: "the phone writes it with PUT /v1/documents/" + key },
    );
  }
  return document;
}

function checkIfMatch(
  ifMatch: number | undefined,
  currentVersion: number,
  key: DocumentKey,
): void {
  if (ifMatch === undefined || ifMatch === currentVersion) return;
  throw new ToolError(
    "version_conflict",
    `\`${key}\` is at version ${currentVersion}, not ${ifMatch}`,
    { document: key, expected: ifMatch, currentVersion },
  );
}

/**
 * Apply a prepared write, or record it as a suggestion.
 *
 * `propose` is the whole of `museWriteMode: propose` (docs/MUSE_CAPABILITIES.md):
 * the invariants have already been checked, so a proposal is always a legal
 * change, and nothing is written and no mutation is appended until it is
 * accepted. A proposal is not yet a change, and the mutation log is the log of
 * changes.
 */
async function commit(
  ctx: WriteContext,
  prepared: Prepared,
  mode: WriteMode,
): Promise<Record<string, unknown>> {
  const at = nowOf(ctx);

  if (mode === "propose") {
    const suggestion = await recordSuggestion(ctx.db, {
      id: `muse_${ulid()}`,
      createdAt: at,
      source: "muse",
      kind: prepared.kind,
      text: prepared.summary,
      action: { kind: prepared.kind, payload: prepared.payload },
    });
    return {
      status: "proposed" satisfies WriteStatus,
      writeMode: mode,
      suggestionId: suggestion.id,
      document: prepared.key,
      changed: prepared.changed,
      summary: prepared.summary,
      pendingSuggestions: (await listSuggestions(ctx.db, { status: "pending" })).length,
      hint: "`museWriteMode` is `propose`: nothing changed. Accept it in the app, or with accept_suggestion.",
    };
  }

  const outcome = await writeDocument(ctx.db, prepared.key, prepared.body, {
    expectedVersion: prepared.currentVersion,
    updatedBy: "muse",
    updatedAt: at,
  });
  if (!outcome.ok) {
    throw new ToolError(
      "version_conflict",
      `\`${prepared.key}\` moved to version ${outcome.currentVersion} while this write was being prepared`,
      {
        document: prepared.key,
        expected: prepared.currentVersion,
        currentVersion: outcome.currentVersion,
      },
    );
  }

  // Appended after the document write, and marked applied in the same breath:
  // Tier 1 is applied by the Worker (docs/EXPORT_SCHEMA.md §3). The phone still
  // drains it, to catch its local copy up offline.
  const mutation = await appendMutation(ctx.db, {
    kind: prepared.kind,
    payload: prepared.payload,
    actor: "muse",
    createdAt: at,
    appliedAt: at,
  });

  return {
    status: "applied" satisfies WriteStatus,
    writeMode: mode,
    document: {
      key: prepared.key,
      version: outcome.document.version,
      updatedAt: outcome.document.updatedAt,
      updatedBy: outcome.document.updatedBy,
    },
    changed: prepared.changed,
    summary: prepared.summary,
    mutationId: mutation.id,
  };
}

/**
 * Queue a mutation for the phone and answer `pending_device_apply`.
 *
 * Used by every Tier-2 tool, and by the two Tier-1 kinds whose state lives only
 * on the device. The push is best-effort by design: the phone also drains on
 * foreground and on background refresh, so a push that never arrives costs
 * latency, not correctness.
 */
async function queue(
  ctx: WriteContext,
  kind: MutationKind,
  payload: unknown,
  summary: string,
  extra: Record<string, unknown> = {},
): Promise<Record<string, unknown>> {
  const at = nowOf(ctx);
  const mutation = await appendMutation(ctx.db, {
    kind,
    payload,
    actor: "muse",
    createdAt: at,
    appliedAt: null,
  });

  let devicePush: PushResult | { error: string } = { sent: 0, failed: 0, skipped: "not_configured" };
  if (ctx.wake) {
    try {
      devicePush = await ctx.wake();
    } catch (error) {
      devicePush = { error: error instanceof Error ? error.message : String(error) };
    }
  }

  return {
    status: "pending_device_apply" satisfies WriteStatus,
    mutationId: mutation.id,
    queuedAt: at,
    summary,
    pendingMutations: await countPending(ctx.db),
    devicePush,
    hint: "The phone applies this and writes to Apple Health. Do not report it as logged until `appliedAt` is set.",
    ...extra,
  };
}

/* ------------------------------------------------------------- set_targets -- */

/** Plain rendering for a change line: no locale, no thousands separator. */
const show = (value: unknown) => String(value);

function diff(before: Record<string, unknown>, after: Record<string, unknown>): Change[] {
  return Object.keys(after)
    .filter((field) => before[field] !== after[field])
    .map((field) => ({ field, from: before[field] ?? null, to: after[field] }));
}

async function prepareTargets(
  ctx: WriteContext,
  patch: z.infer<typeof TargetsPatch>,
  ifMatch?: number,
): Promise<Prepared> {
  if (Object.keys(patch).length === 0) {
    throw new ToolError("nothing_to_write", "name at least one target to change", {
      fields: Object.keys(TargetsPatch.shape),
    });
  }

  const current = await requireDocument(ctx, "goalSettings", readGoalSettings);
  checkIfMatch(ifMatch, current.version, "goalSettings");

  const targets = { ...current.targets, ...patch };
  const body = parseArgs(
    GoalSettingsBody,
    stripEnvelope({ ...current, targets }),
  );

  const issues = checkGoalSettings(body);
  if (issues.length > 0) reject(issues, "goalSettings");

  const changed = diff(current.targets as Record<string, unknown>, targets);
  return {
    key: "goalSettings",
    kind: "set_targets",
    body,
    // §3: the payload is the partial the caller sent, not the merged document.
    payload: patch,
    currentVersion: current.version,
    changed,
    summary:
      changed.length === 0
        ? "targets unchanged"
        : `targets: ${changed
            .map((change) => `${change.field} ${show(change.from)} → ${show(change.to)}`)
            .join(", ")}`,
  };
}

/** `version`/`updatedAt`/`updatedBy` are columns, never part of a body. */
function stripEnvelope(document: Record<string, unknown>): Record<string, unknown> {
  const { version, updatedAt, updatedBy, ...body } = document;
  void version;
  void updatedAt;
  void updatedBy;
  return body;
}

/**
 * One schema, used both as the tool's advertised input and as the gate inside
 * `run`: the field names live in exactly one place.
 */
const setTargetsArgs = z.strictObject({
  kcal: z.number().int().optional().describe("Daily calorie target, 1400-4000."),
  proteinG: z.number().int().optional().describe("Daily protein target in grams."),
  proteinMinG: z
    .number()
    .int()
    .optional()
    .describe(
      "Protein floor in grams - the consistency grid's protein win. Must not exceed `proteinG`.",
    ),
  fatMinG: z.number().int().optional().describe("Fat floor in grams. Never below 60."),
  fatMaxG: z.number().int().optional().describe("Fat ceiling in grams."),
  steps: z.number().int().optional().describe("Daily step target."),
  sleepMinutes: z.number().int().optional().describe("Nightly sleep target in minutes."),
  ...ifMatchArg,
});

const setTargets = defineWrite({
  name: "set_targets",
  title: "Set calorie and macro targets",
  description:
    "Change the daily calorie and macro targets. Send only the fields you are changing; the rest keep their current values. Hard limits, enforced here and never clamped: calories within 1400–4000, fat floor at least 60 g, protein floor no higher than the protein target. Takes effect at once unless `museWriteMode` is `propose`.",
  inputSchema: setTargetsArgs,
  async run(args, ctx) {
    const { mode } = await writeGate(ctx);
    const { ifMatch, ...patch } = parseArgs(setTargetsArgs, args);
    return commit(ctx, await prepareTargets(ctx, patch, ifMatch), mode);
  },
});

/* ---------------------------------------------------------- update_program -- */

const WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] as const;

const updateProgramArgs = z.strictObject({
  program: ProgramBody.describe("The full `program` document body."),
  ...ifMatchArg,
});

async function prepareProgram(
  ctx: WriteContext,
  program: z.infer<typeof ProgramBody>,
  ifMatch?: number,
): Promise<Prepared> {
  const issues = checkProgram(program);
  if (issues.length > 0) reject(issues, "program");

  const currentVersion = await documentVersion(ctx.db, "program");
  checkIfMatch(ifMatch, currentVersion, "program");
  const before = await readProgram(ctx.db);

  const order = (days: z.infer<typeof ProgramBody>["days"]) =>
    days.slice().sort((a, b) => a.weekday - b.weekday);
  const week = order(program.days)
    .map((day) => `${WEEKDAY_NAMES[day.weekday - 1]} ${day.kind}`)
    .join(", ");

  return {
    key: "program",
    kind: "update_program",
    body: program,
    // §3: the payload is the full program body.
    payload: program,
    currentVersion,
    changed: [
      { field: "name", from: before?.name ?? null, to: program.name },
      {
        field: "days",
        from: before ? order(before.days).map((day) => day.kind) : null,
        to: order(program.days).map((day) => day.kind),
      },
      { field: "deload.active", from: before?.deload.active ?? null, to: program.deload.active },
    ],
    summary: `program "${program.name}": ${week}`,
  };
}

const updateProgram = defineWrite({
  name: "update_program",
  title: "Update the training program",
  description:
    "Replace the whole weekly program: which weekday is which session, the exercises in each session, sets and reps, the finisher, the progression rule and the deload state. `days` holds exactly seven entries, ISO weekday 1 = Monday. Spec §F5 is enforced here: two non-rest days training the same muscle region may not sit less than 48 h apart, and the week wraps, so Sunday and Monday are checked too. A week that breaks it is rejected with the offending pair named.",
  inputSchema: updateProgramArgs,
  async run(args, ctx) {
    const { mode } = await writeGate(ctx);
    const { program, ifMatch } = parseArgs(updateProgramArgs, args);
    return commit(ctx, await prepareProgram(ctx, program, ifMatch), mode);
  },
});

/* ---------------------------------------------------------------- set_flag -- */

/**
 * A union, because `museWriteMode` is the one flag that is not a boolean: a
 * `true` written to it would be a document the app cannot decode. The tool
 * advertises the flat shape below -- a union of two objects is poor JSON Schema
 * for a client to fill in -- and this is what actually gates the write.
 */
const setFlagArgs = z.union([
  z.strictObject({
    key: z.literal("museWriteMode"),
    value: z.enum(["apply", "propose"]),
    ...ifMatchArg,
  }),
  z.strictObject({
    key: z.enum([
      "remoteBridgeEnabled",
      "museWritesEnabled",
      "rawDetailSyncEnabled",
      "foundationModelsEnabled",
    ]),
    value: z.boolean(),
    ...ifMatchArg,
  }),
]);

async function prepareFlag(
  ctx: WriteContext,
  change: z.infer<typeof setFlagArgs>,
): Promise<Prepared> {
  const current = await requireDocument(ctx, "flags", readFlags);
  checkIfMatch(change.ifMatch, current.version, "flags");

  const body = parseArgs(
    FlagsBody,
    stripEnvelope({ ...current, [change.key]: change.value }),
  );
  const from = (current as unknown as Record<string, unknown>)[change.key];

  return {
    key: "flags",
    kind: "set_flag",
    body,
    // §3: `{ key, value }`.
    payload: { key: change.key, value: change.value },
    currentVersion: current.version,
    changed: [{ field: change.key, from: from ?? null, to: change.value }],
    summary: `flags.${change.key}: ${show(from)} → ${show(change.value)}`,
  };
}

const setFlag = defineWrite({
  name: "set_flag",
  title: "Set a feature flag",
  description:
    "Flip one feature flag. `museWriteMode` is `apply` or `propose` — `propose` turns every settings write into a pending suggestion for one-tap accept in the app. The other flags are booleans: `remoteBridgeEnabled`, `museWritesEnabled`, `rawDetailSyncEnabled`, `foundationModelsEnabled`. Launch-phase behaviour is a flag flip, never a release.",
  inputSchema: z.strictObject({
    key: z
      .enum([
        "remoteBridgeEnabled",
        "museWritesEnabled",
        "museWriteMode",
        "rawDetailSyncEnabled",
        "foundationModelsEnabled",
      ])
      .describe("Which flag to set."),
    value: z
      .union([z.boolean(), z.enum(["apply", "propose"])])
      .describe("`apply` or `propose` for `museWriteMode`; a boolean for every other flag."),
    ...ifMatchArg,
  }),
  async run(args, ctx) {
    const { mode } = await writeGate(ctx);
    return commit(ctx, await prepareFlag(ctx, parseArgs(setFlagArgs, args)), mode);
  },
});

/* ------------------------------------------------------------- set_staples -- */

const setStaplesArgs = z.strictObject({ staples: StaplesPayload.shape.staples });

function staplesSummary(staples: Array<{ name: string }>): string {
  const names = staples.map((item) => item.name);
  return `staples → ${staples.length} item${staples.length === 1 ? "" : "s"}${
    names.length > 0 ? `: ${names.slice(0, 4).join(", ")}${names.length > 4 ? ", …" : ""}` : ""
  }`;
}

const setStaples = defineWrite({
  name: "set_staples",
  title: "Set the staple foods",
  description:
    "Replace the one-tap quick-add staples list. Macros are per 100 g for every food, so portions scale uniformly; `servingGrams` is what one tap logs. The staples list lives on the phone, so this queues and returns `pending_device_apply`.",
  inputSchema: z.strictObject({
    staples: StaplesPayload.shape.staples.describe(
      "The whole staples list, replacing the current one. Macros per 100 g.",
    ),
  }),
  async run(args, ctx) {
    const { mode } = await writeGate(ctx);
    const { staples } = parseArgs(setStaplesArgs, args);
    const summary = staplesSummary(staples);

    if (mode === "propose") {
      const suggestion = await recordSuggestion(ctx.db, {
        id: `muse_${ulid()}`,
        createdAt: nowOf(ctx),
        source: "muse",
        kind: "set_staples",
        text: summary,
        action: { kind: "set_staples", payload: { staples } },
      });
      return {
        status: "proposed" satisfies WriteStatus,
        writeMode: mode,
        suggestionId: suggestion.id,
        summary,
        hint: "`museWriteMode` is `propose`: nothing was queued. Accept it in the app, or with accept_suggestion.",
      };
    }

    // Tier 1 in the log, but there is no `staples` document in D1: the quick-add
    // list is the phone's own state (`LocalStateApplier.applyStaples`). So this
    // queues like Tier 2 and says so, rather than claiming an apply the cloud
    // did not make.
    return queue(ctx, "set_staples", { staples }, summary, { writeMode: mode });
  },
});

/* ------------------------------------------------------- accept_suggestion -- */

const acceptSuggestionArgs = z.strictObject({
  suggestionId: z.string().min(1).max(64),
});

const acceptSuggestion = defineWrite({
  name: "accept_suggestion",
  title: "Accept a suggestion",
  description:
    "Accept an open suggestion by id — the weekly calorie auto-adjust the app raised, or a change you proposed while `museWriteMode` was `propose`. The suggestion's own change is then applied. An id that is not open is rejected, with the open ids listed.",
  inputSchema: z.strictObject({
    suggestionId: z
      .string()
      .min(1)
      .max(64)
      .describe("The suggestion's id, as the proposing tool or the app reported it."),
  }),
  async run(args, ctx) {
    // Deliberately *not* gated on `museWriteMode`: accepting is how a proposal
    // becomes a change, so routing it through the propose path would make
    // `propose` a mode nothing could ever leave.
    await writeGate(ctx);
    const { suggestionId } = parseArgs(acceptSuggestionArgs, args);

    const suggestion = await getSuggestion(ctx.db, suggestionId);
    if (!suggestion) {
      const open = await listSuggestions(ctx.db, { status: "pending" });
      throw new ToolError("unknown_suggestion", `no suggestion with id ${suggestionId}`, {
        openSuggestions: open.map((item) => ({ id: item.id, text: item.text })),
      });
    }
    if (suggestion.status !== "pending") {
      throw new ToolError(
        "already_decided",
        `suggestion ${suggestionId} was already accepted at ${suggestion.decidedAt}`,
        { suggestionId, decidedAt: suggestion.decidedAt },
      );
    }

    const claimed = await markAccepted(ctx.db, suggestionId, nowOf(ctx));
    if (!claimed) {
      throw new ToolError(
        "already_decided",
        `suggestion ${suggestionId} was decided while this call was in flight`,
        { suggestionId },
      );
    }

    // The acceptance itself is logged first, so the phone's own ledger learns
    // why its pending list cleared; the change it implies follows.
    const acceptance = await appendMutation(ctx.db, {
      kind: "accept_suggestion",
      payload: { suggestionId },
      actor: "muse",
      createdAt: nowOf(ctx),
      appliedAt: null,
    });

    const action = suggestion.action;
    if (!action) {
      // A suggestion only the phone can apply -- it raised it, and it knows the
      // id. Queued rather than guessed at.
      const result = await queue(
        ctx,
        "accept_suggestion",
        { suggestionId },
        `accepted: ${suggestion.text}`,
        { suggestionId, acceptanceMutationId: acceptance.id },
      );
      return result;
    }

    const applied = await applyAction(ctx, action.kind, action.payload);
    return {
      ...applied,
      suggestionId,
      acceptanceMutationId: acceptance.id,
      summary: `accepted: ${suggestion.text}`,
    };
  },
});

/**
 * Perform the change a suggestion carries, in `apply` semantics whatever the
 * flag says — the owner has just said yes to this one.
 *
 * It commits directly rather than calling the tool's own `run`: `run` would
 * consult `museWriteMode` again and propose the proposal a second time, so
 * `propose` would be a mode nothing could ever leave. `If-Match` is not
 * forwarded either, since the suggestion was made against an older version and
 * accepting it means "do this now".
 */
async function applyAction(
  ctx: WriteContext,
  kind: MutationKind,
  payload: unknown,
): Promise<Record<string, unknown>> {
  switch (kind) {
    case "set_targets":
      return commit(ctx, await prepareTargets(ctx, parseArgs(TargetsPatch, payload)), "apply");
    case "update_program":
      return commit(ctx, await prepareProgram(ctx, parseArgs(ProgramBody, payload)), "apply");
    case "set_flag":
      return commit(ctx, await prepareFlag(ctx, parseArgs(setFlagArgs, payload)), "apply");
    case "set_staples": {
      const { staples } = parseArgs(setStaplesArgs, payload);
      return queue(ctx, "set_staples", { staples }, staplesSummary(staples));
    }
    default:
      // Every Tier-2 kind, and `accept_suggestion` itself: queue it.
      return queue(ctx, kind, payload, `applied ${kind}`);
  }
}

/* ------------------------------------------------------------ Tier 2 — logs -- */

const logMeal = defineWrite({
  name: "log_meal",
  title: "Log a meal",
  description:
    "Log a meal for one day. Items carry absolute macros for the portion eaten, not per 100 g. Returns `pending_device_apply`: the phone writes the dietary energy, protein, carbohydrate and fat samples to Apple Health, which can only be written from the device — so do not report this as logged until the phone has applied it.",
  inputSchema: z.strictObject({
    date: isoDate.describe("The day the meal was eaten, YYYY-MM-DD in the user's timezone."),
    meal: LogMealPayload.shape.meal.describe("breakfast, lunch, dinner or snack."),
    items: LogMealPayload.shape.items.describe(
      "One entry per food, with the absolute macros of the portion eaten.",
    ),
  }),
  async run(args, ctx) {
    await writeGate(ctx);
    const payload = parseArgs(LogMealPayload, args);
    const total = (field: "kcal" | "proteinG") =>
      Math.round(payload.items.reduce((sum, item) => sum + item[field], 0));
    return queue(
      ctx,
      "log_meal",
      payload,
      `${payload.meal} on ${payload.date}: ${payload.items.length} item${
        payload.items.length === 1 ? "" : "s"
      }, ${total("kcal")} kcal, ${total("proteinG")} g protein`,
    );
  },
});

const logWater = defineWrite({
  name: "log_water",
  title: "Log water",
  description:
    "Log water in millilitres for one day. Returns `pending_device_apply`: the HealthKit write happens on the phone.",
  inputSchema: z.strictObject({
    date: isoDate.describe("The day, YYYY-MM-DD."),
    ml: LogWaterPayload.shape.ml.describe("Millilitres drunk."),
  }),
  async run(args, ctx) {
    await writeGate(ctx);
    const payload = parseArgs(LogWaterPayload, args);
    return queue(ctx, "log_water", payload, `water on ${payload.date}: ${payload.ml} ml`);
  },
});

const logTopSet = defineWrite({
  name: "log_top_set",
  title: "Log a top set",
  description:
    "Log the heaviest working set of one exercise: weight in kg and reps. Feeds the on-device progression view, so it returns `pending_device_apply`. This is not workout recording — the Apple Watch records; this records the number that drives progression.",
  inputSchema: z.strictObject({
    date: isoDate.describe("The day, YYYY-MM-DD."),
    exerciseId: LogTopSetPayload.shape.exerciseId.describe(
      "A free-exercise-db id, e.g. `Goblet_Squat`.",
    ),
    weightKg: LogTopSetPayload.shape.weightKg.describe("Weight in kilograms."),
    reps: LogTopSetPayload.shape.reps.describe("Reps completed."),
  }),
  async run(args, ctx) {
    await writeGate(ctx);
    const payload = parseArgs(LogTopSetPayload, args);
    return queue(
      ctx,
      "log_top_set",
      payload,
      `${payload.exerciseId} ${payload.weightKg} kg × ${payload.reps} on ${payload.date}`,
    );
  },
});

const logCheckin = defineWrite({
  name: "log_checkin",
  title: "Log the morning check-in",
  description:
    "Log the morning check-in: energy 1–5, and soreness for each of the eight muscle groups as none, mild or sore. All eight groups are required — a missing group is not the same as `none`. Returns `pending_device_apply`.",
  inputSchema: z.strictObject({
    date: isoDate.describe("The day, YYYY-MM-DD."),
    energy: LogCheckInPayload.shape.energy.describe("Energy, 1 (flat) to 5 (fresh)."),
    soreness: LogCheckInPayload.shape.soreness.describe(
      "none, mild or sore for each of chest, back, shoulders, arms, quads, hamstrings, glutes and core.",
    ),
  }),
  async run(args, ctx) {
    await writeGate(ctx);
    const payload = parseArgs(LogCheckInPayload, args);
    const sore = Object.entries(payload.soreness)
      .filter(([, level]) => level === "sore")
      .map(([group]) => group);
    return queue(
      ctx,
      "log_checkin",
      payload,
      `check-in on ${payload.date}: energy ${payload.energy}${
        sore.length > 0 ? `, sore: ${sore.join(", ")}` : ", nothing sore"
      }`,
    );
  },
});

const scheduleWorkout = defineWrite({
  name: "schedule_workout",
  title: "Send a session to the Watch",
  description:
    "Schedule one of the program's sessions on the Apple Watch for a given day. WorkoutKit schedules from the device, so this returns `pending_device_apply`. The session must be one the program defines — there are no exercises to send otherwise — and `rest` cannot be scheduled.",
  inputSchema: z.strictObject({
    date: isoDate.describe("The day to schedule it for, YYYY-MM-DD."),
    sessionKind: SessionKind.describe("Which session, e.g. `upperA`. Not `rest`."),
  }),
  async run(args, ctx) {
    await writeGate(ctx);
    const payload = parseArgs(ScheduleWorkoutPayload, args);

    if (payload.sessionKind === "rest") {
      throw new ToolError("not_schedulable", "`rest` is not a session the Watch can run", {
        sessionKind: payload.sessionKind,
      });
    }
    const program = await requireDocument(ctx, "program", readProgram);
    const session = program.sessions[payload.sessionKind];
    if (!session) {
      throw new ToolError(
        "unknown_session",
        `the program does not define ${payload.sessionKind}, so there are no exercises to send`,
        {
          sessionKind: payload.sessionKind,
          definedSessions: Object.keys(program.sessions),
        },
      );
    }

    return queue(
      ctx,
      "schedule_workout",
      payload,
      `${session.name} (${payload.sessionKind}) to the Watch for ${payload.date}`,
    );
  },
});

const triggerExport = defineWrite({
  name: "trigger_export",
  title: "Force an export",
  description:
    "Ask the phone to write the export files to the iCloud Drive folder now, rather than waiting for the nightly job. Returns `pending_device_apply`.",
  inputSchema: z.strictObject({}),
  async run(args, ctx) {
    await writeGate(ctx);
    parseArgs(TriggerExportPayload, args ?? {});
    return queue(ctx, "trigger_export", {}, "export requested");
  },
});

/** Tier 1 first, then Tier 2, in the order docs/EXPORT_SCHEMA.md §3 lists them. */
export const writeTools: WriteTool[] = [
  setTargets,
  updateProgram,
  setStaples,
  setFlag,
  acceptSuggestion,
  logMeal,
  logWater,
  logTopSet,
  logCheckin,
  scheduleWorkout,
  triggerExport,
];
