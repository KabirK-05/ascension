/**
 * The invariants, as pure functions over value types.
 *
 * These are the rules that make Muse structurally unable to author a bad week or
 * a bad set of targets, so they are tested on their own as well as through the
 * tools: a rule that only ever runs behind a tool is a rule nobody can read.
 */
import { describe, expect, it } from "vitest";
import type { ProgramBody } from "../src/contract";
import {
  ABSOLUTE_FAT_FLOOR_G,
  checkGoalSettings,
  checkProgram,
  checkRecovery,
  KCAL_MAX,
  KCAL_MIN,
  RECOVERY_HOURS,
  trainedRegions,
} from "../src/guardrails";
import { GOAL_SETTINGS, PROGRAM, programWith } from "./fixtures";

type Kind = (typeof PROGRAM)["days"][number]["kind"];

/** A week from seven session kinds, Monday first. */
function week(kinds: Kind[]): ProgramBody {
  return programWith(kinds.map((kind, index) => ({ weekday: index + 1, kind })));
}

const messages = (issues: Array<{ message: string }>) =>
  issues.map((issue) => issue.message).join(" | ");

describe("goalSettings invariants (docs/EXPORT_SCHEMA.md §2.1)", () => {
  it("accepts the seeded document", () => {
    expect(checkGoalSettings(GOAL_SETTINGS)).toEqual([]);
  });

  it("rejects a fat floor under 60 g, and says what it found", () => {
    const issues = checkGoalSettings({
      ...GOAL_SETTINGS,
      targets: { ...GOAL_SETTINGS.targets, fatMinG: 59 },
    });
    expect(issues).toHaveLength(1);
    expect(issues[0]?.path).toBe("targets.fatMinG");
    expect(issues[0]?.message).toContain(`at least ${ABSOLUTE_FAT_FLOOR_G} g`);
    expect(issues[0]?.message).toContain("59");
  });

  it("accepts exactly the fat floor", () => {
    expect(
      checkGoalSettings({
        ...GOAL_SETTINGS,
        targets: { ...GOAL_SETTINGS.targets, fatMinG: ABSOLUTE_FAT_FLOOR_G },
      }),
    ).toEqual([]);
  });

  it("rejects an inverted fat range", () => {
    const issues = checkGoalSettings({
      ...GOAL_SETTINGS,
      targets: { ...GOAL_SETTINGS.targets, fatMinG: 90, fatMaxG: 70 },
    });
    expect(messages(issues)).toContain("must not exceed targets.fatMaxG");
  });

  it.each([
    [KCAL_MIN - 1, "below"],
    [KCAL_MAX + 1, "above"],
  ])("rejects %i kcal, %s the range", (kcal) => {
    const issues = checkGoalSettings({
      ...GOAL_SETTINGS,
      targets: { ...GOAL_SETTINGS.targets, kcal },
    });
    expect(issues.map((issue) => issue.path)).toContain("targets.kcal");
    expect(messages(issues)).toContain(`${KCAL_MIN}...${KCAL_MAX}`);
  });

  it.each([KCAL_MIN, KCAL_MAX])("accepts %i kcal, on the boundary", (kcal) => {
    expect(
      checkGoalSettings({
        ...GOAL_SETTINGS,
        targets: { ...GOAL_SETTINGS.targets, kcal },
      }),
    ).toEqual([]);
  });

  it("rejects a protein floor above the protein target", () => {
    const issues = checkGoalSettings({
      ...GOAL_SETTINGS,
      targets: { ...GOAL_SETTINGS.targets, proteinG: 150, proteinMinG: 151 },
    });
    expect(issues[0]?.path).toBe("targets.proteinMinG");
  });

  it("accepts a protein floor equal to the target", () => {
    expect(
      checkGoalSettings({
        ...GOAL_SETTINGS,
        targets: { ...GOAL_SETTINGS.targets, proteinG: 150, proteinMinG: 150 },
      }),
    ).toEqual([]);
  });

  it.each([
    [["beef"], "pork"],
    [["pork"], "beef"],
    [[], "pork, beef"],
  ])("rejects excludedMeats %j, naming what is missing", (excludedMeats, missing) => {
    const issues = checkGoalSettings({
      ...GOAL_SETTINGS,
      dietaryRules: { ...GOAL_SETTINGS.dietaryRules, excludedMeats },
    });
    expect(issues[0]?.path).toBe("dietaryRules.excludedMeats");
    expect(issues[0]?.message).toContain(missing);
  });

  it("reads excludedMeats case-insensitively", () => {
    expect(
      checkGoalSettings({
        ...GOAL_SETTINGS,
        dietaryRules: { ...GOAL_SETTINGS.dietaryRules, excludedMeats: ["Pork", "BEEF"] },
      }),
    ).toEqual([]);
  });

  it("reports every violation at once, not just the first", () => {
    const issues = checkGoalSettings({
      ...GOAL_SETTINGS,
      targets: { ...GOAL_SETTINGS.targets, kcal: 900, fatMinG: 10, proteinMinG: 200 },
      dietaryRules: { ...GOAL_SETTINGS.dietaryRules, excludedMeats: [] },
    });
    expect(issues).toHaveLength(4);
  });
});

describe("the §F5 recovery rule", () => {
  it("knows which regions each session loads", () => {
    expect(trainedRegions("upperA")).toEqual(["upperBody"]);
    expect(trainedRegions("lowerB")).toEqual(["lowerBody"]);
    expect(trainedRegions("fullBody")).toEqual(["upperBody", "lowerBody"]);
    expect(trainedRegions("zone2")).toEqual([]);
    expect(trainedRegions("rest")).toEqual([]);
  });

  it("accepts the four-day Upper/Lower split the contract prints", () => {
    expect(checkProgram(PROGRAM)).toEqual([]);
  });

  it("rejects two upper days back to back, and names the pair", () => {
    const issues = checkRecovery(
      week(["upperA", "upperB", "rest", "lowerA", "rest", "lowerB", "rest"]),
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]?.message).toBe(
      `weekdays 1 (upperA) and 2 (upperB) both train upperBody less than ${RECOVERY_HOURS} h apart`,
    );
  });

  it("accepts the same region exactly 48 h apart — the boundary is `less than`", () => {
    // Mon and Wed are two calendar days apart: exactly 48 h, so legal. This is
    // the shape the program actually uses, so the boundary is the rule.
    expect(
      checkRecovery(week(["upperA", "lowerA", "upperB", "lowerB", "rest", "rest", "rest"])),
    ).toEqual([]);
  });

  it("rejects the same region 24 h apart at the Sunday → Monday wrap", () => {
    const issues = checkRecovery(
      week(["upperA", "lowerA", "rest", "lowerB", "rest", "rest", "upperB"]),
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]?.message).toBe(
      `weekdays 7 (upperB) and 1 (upperA) both train upperBody less than ${RECOVERY_HOURS} h apart`,
    );
  });

  it("rejects a full-body day next to an upper day, on the shared region", () => {
    const issues = checkRecovery(
      week(["fullBody", "upperA", "rest", "rest", "rest", "rest", "rest"]),
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]?.message).toContain("upperBody");
  });

  it("rejects back-to-back full-body days once per shared region", () => {
    const issues = checkRecovery(
      week(["fullBody", "fullBody", "rest", "rest", "rest", "rest", "rest"]),
    );
    expect(issues.map((issue) => issue.message.match(/train (\w+)/)?.[1]).sort()).toEqual([
      "lowerBody",
      "upperBody",
    ]);
  });

  it("allows conditioning on consecutive days — Zone 2 loads no lifting region", () => {
    expect(
      checkRecovery(week(["zone2", "zone2", "upperA", "lowerA", "rest", "rest", "rest"])),
    ).toEqual([]);
  });

  it("allows the historical Mon/Thu full-body plus Wed/Sat Zone 2 shape (spec §3)", () => {
    expect(
      checkProgram(
        week(["fullBody", "rest", "zone2", "fullBody", "rest", "zone2", "rest"]),
      ),
    ).toEqual([]);
  });

  it("reports every offending pair, so one rejection names the whole problem", () => {
    const issues = checkRecovery(
      week(["upperA", "upperB", "lowerA", "lowerB", "rest", "rest", "rest"]),
    );
    expect(issues).toHaveLength(2);
  });
});

describe("program shape", () => {
  it("rejects a week that is not seven days", () => {
    const short = { ...PROGRAM, days: PROGRAM.days.slice(0, 6) };
    expect(messages(checkProgram(short))).toContain("exactly 7 entries, found 6");
  });

  it("rejects a week that covers a weekday twice", () => {
    const duplicated: ProgramBody = {
      ...PROGRAM,
      days: [
        { weekday: 1, kind: "upperA" },
        { weekday: 1, kind: "lowerA" },
        { weekday: 3, kind: "rest" },
        { weekday: 4, kind: "upperB" },
        { weekday: 5, kind: "lowerB" },
        { weekday: 6, kind: "rest" },
        { weekday: 7, kind: "rest" },
      ],
    };
    expect(messages(checkProgram(duplicated))).toContain("exactly once");
  });

  it("rejects a planned day with no session template", () => {
    const missing: ProgramBody = {
      ...PROGRAM,
      sessions: { ...PROGRAM.sessions, upperB: undefined },
    };
    expect(messages(checkProgram(missing))).toContain(
      "program.days references upperB but program.sessions has no entry",
    );
  });

  it("rejects a session template no day plans", () => {
    const orphan: ProgramBody = {
      ...PROGRAM,
      sessions: {
        ...PROGRAM.sessions,
        fullBody: { name: "Full Body", exercises: PROGRAM.sessions.upperA?.exercises ?? [] },
      },
    };
    expect(messages(checkProgram(orphan))).toContain(
      "program.sessions defines fullBody but no day plans it",
    );
  });

  it("rejects an empty session", () => {
    const empty: ProgramBody = {
      ...PROGRAM,
      sessions: { ...PROGRAM.sessions, lowerA: { name: "Lower A", exercises: [] } },
    };
    expect(messages(checkProgram(empty))).toContain("program.sessions[lowerA] has no exercises");
  });

  it("checks every session kind the contract declares", () => {
    const kinds: Kind[] = [
      "upperA",
      "upperB",
      "lowerA",
      "lowerB",
      "fullBody",
      "zone2",
      "rest",
    ];
    for (const kind of kinds) expect(trainedRegions(kind)).toBeDefined();
  });
});
