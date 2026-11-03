/**
 * The invariants a write is rejected for, never clamped to.
 *
 * Muse writes with full authority and no confirmation, so this file is the only
 * thing between a bad tool call and a bad training week. Every check here
 * mirrors a check `AscensionCore` already makes in Swift
 * (`GoalSettingsDocument.validate()`, `ProgramDocument.validate()`): the phone
 * writes the same documents through `PUT /v1/documents/<key>`, and a rule the
 * Worker enforced and the device did not — or the reverse — would mean a document
 * one half of the loop cannot store. The wording follows
 * `DomainValidationError.description` so a rejection reads the same on both
 * sides.
 */
import {
  type GoalSettingsBody,
  type MuscleGroup,
  type ProgramBody,
  sessionKinds,
} from "./contract";

/* --------------------------------------------------------- goalSettings §2 -- */

export const KCAL_MIN = 1400;
export const KCAL_MAX = 4000;
export const ABSOLUTE_FAT_FLOOR_G = 60;
/** Spec §2 is a hard constraint, not a preference: chicken and eggs only. */
export const REQUIRED_EXCLUDED_MEATS = ["pork", "beef"] as const;

export type Issue = { path: string; message: string };

/**
 * docs/EXPORT_SCHEMA.md §2.1. Every violation is reported, not just the first:
 * a patch that breaks two invariants should come back fixable in one pass.
 */
export function checkGoalSettings(body: GoalSettingsBody): Issue[] {
  const issues: Issue[] = [];
  const { targets, dietaryRules } = body;

  if (targets.fatMinG < ABSOLUTE_FAT_FLOOR_G) {
    issues.push({
      path: "targets.fatMinG",
      message: `targets.fatMinG must be at least ${ABSOLUTE_FAT_FLOOR_G} g, found ${targets.fatMinG}`,
    });
  }
  if (targets.fatMinG > targets.fatMaxG) {
    issues.push({
      path: "targets.fatMaxG",
      message: `targets.fatMinG (${targets.fatMinG}) must not exceed targets.fatMaxG (${targets.fatMaxG})`,
    });
  }
  if (targets.kcal < KCAL_MIN || targets.kcal > KCAL_MAX) {
    issues.push({
      path: "targets.kcal",
      message: `targets.kcal must be within ${KCAL_MIN}...${KCAL_MAX}, found ${targets.kcal}`,
    });
  }
  if (targets.proteinMinG > targets.proteinG) {
    issues.push({
      path: "targets.proteinMinG",
      message: `targets.proteinMinG (${targets.proteinMinG}) must not exceed targets.proteinG (${targets.proteinG})`,
    });
  }

  const excluded = new Set(dietaryRules.excludedMeats.map((meat) => meat.toLowerCase()));
  const missing = REQUIRED_EXCLUDED_MEATS.filter((meat) => !excluded.has(meat));
  if (missing.length > 0) {
    issues.push({
      path: "dietaryRules.excludedMeats",
      message: `dietaryRules.excludedMeats must contain ${missing.join(", ")}`,
    });
  }

  return issues;
}

/* --------------------------------------------------------------- program §F5 -- */

export const WEEKDAY_COUNT = 7;
/** Consecutive ISO weekdays are 24 h apart; the rule's threshold is 48 h. */
export const RECOVERY_HOURS = 48;

export const muscleRegions = ["upperBody", "lowerBody"] as const;
export type MuscleRegion = (typeof muscleRegions)[number];

/**
 * The regions a session loads. Mirrors `SessionKind.trainedRegions` in
 * AscensionCore; conditioning and rest load no lifting region, so two Zone 2
 * days in a row are legal and two Upper days in a row are not.
 */
const TRAINED_REGIONS: Record<(typeof sessionKinds)[number], readonly MuscleRegion[]> = {
  upperA: ["upperBody"],
  upperB: ["upperBody"],
  lowerA: ["lowerBody"],
  lowerB: ["lowerBody"],
  fullBody: ["upperBody", "lowerBody"],
  zone2: [],
  rest: [],
};

/** Which check-in groups make up each region. `core` belongs to neither. */
export const regionGroups: Record<MuscleRegion, readonly MuscleGroup[]> = {
  upperBody: ["chest", "back", "shoulders", "arms"],
  lowerBody: ["quads", "hamstrings", "glutes"],
};

export function trainedRegions(
  kind: (typeof sessionKinds)[number],
): readonly MuscleRegion[] {
  return TRAINED_REGIONS[kind];
}

export function isTrainingDay(kind: (typeof sessionKinds)[number]): boolean {
  return kind !== "rest";
}

/**
 * docs/EXPORT_SCHEMA.md §2.2 and spec §F5. The program is the one document where
 * a legal-looking write can be wrong: Muse must be structurally unable to author
 * an invalid week.
 */
export function checkProgram(body: ProgramBody): Issue[] {
  const issues: Issue[] = [];

  if (body.days.length !== WEEKDAY_COUNT) {
    issues.push({
      path: "days",
      message: `program.days must hold exactly ${WEEKDAY_COUNT} entries, found ${body.days.length}`,
    });
  }

  const weekdays = body.days.map((day) => day.weekday).sort((a, b) => a - b);
  const expected = Array.from({ length: WEEKDAY_COUNT }, (_, i) => i + 1);
  if (
    weekdays.length !== expected.length ||
    weekdays.some((weekday, index) => weekday !== expected[index])
  ) {
    issues.push({
      path: "days",
      message: `program.days must cover ISO weekdays 1...${WEEKDAY_COUNT} exactly once, found [${weekdays.join(", ")}]`,
    });
  }

  const planned = new Set(
    body.days.map((day) => day.kind).filter((kind) => isTrainingDay(kind)),
  );
  for (const kind of planned) {
    if (!body.sessions[kind]) {
      issues.push({
        path: `sessions.${kind}`,
        message: `program.days references ${kind} but program.sessions has no entry`,
      });
    }
  }
  for (const [kind, template] of Object.entries(body.sessions)) {
    if (!template) continue;
    if (!planned.has(kind as (typeof sessionKinds)[number])) {
      issues.push({
        path: `sessions.${kind}`,
        message: `program.sessions defines ${kind} but no day plans it`,
      });
    } else if (template.exercises.length === 0) {
      issues.push({
        path: `sessions.${kind}.exercises`,
        message: `program.sessions[${kind}] has no exercises`,
      });
    }
  }

  issues.push(...checkRecovery(body));
  return issues;
}

/**
 * Spec §F5: no two non-rest days training the same region may sit less than 48 h
 * apart. Consecutive weekdays are 24 h apart, and the week repeats, so Sunday
 * and Monday are checked too — a week is a cycle, not a list.
 *
 * Two days apart is exactly 48 h and so is legal: the threshold is "less than",
 * which is what makes Monday/Wednesday Upper the shape the program actually
 * uses. Every offending pair is reported, so one rejection names the whole
 * problem.
 */
export function checkRecovery(body: ProgramBody): Issue[] {
  const issues: Issue[] = [];
  const kindFor = new Map(body.days.map((day) => [day.weekday, day.kind]));

  for (let weekday = 1; weekday <= WEEKDAY_COUNT; weekday += 1) {
    const next = weekday === WEEKDAY_COUNT ? 1 : weekday + 1;
    const first = kindFor.get(weekday);
    const second = kindFor.get(next);
    if (!first || !second) continue;
    const shared = trainedRegions(first)
      .filter((region) => trainedRegions(second).includes(region))
      .sort();
    for (const region of shared) {
      issues.push({
        path: `days.${weekday}`,
        message:
          `weekdays ${weekday} (${first}) and ${next} (${second}) both train ${region} ` +
          `less than ${RECOVERY_HOURS} h apart`,
      });
    }
  }

  return issues;
}
