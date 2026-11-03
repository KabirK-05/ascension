/**
 * Every state the folder can be in. The folder is user data on a synced drive, so none
 * of these may throw and none may turn a missing measurement into a zero.
 */
import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { ExportFolderUnavailable } from "../src/export-folder";
import {
  copyFixture,
  emptyFolderDir,
  fixtureFolder,
  folderAt,
} from "./support/folders";

const temporary: string[] = [];
afterEach(async () => {
  while (temporary.length > 0) {
    await rm(temporary.pop()!, { recursive: true, force: true });
  }
});

async function scratch(create: () => Promise<string>): Promise<string> {
  const dir = await create();
  temporary.push(dir);
  return dir;
}

describe("a full export folder", () => {
  it("reads every day, in order, with no complaint", async () => {
    const { folder, warnings } = fixtureFolder("full");
    const snapshot = await folder.snapshot();

    expect(snapshot.rollups).toHaveLength(28);
    expect(snapshot.latest).toBe("2026-11-30");
    expect(snapshot.rollups[0]!.date).toBe("2026-11-03");
    expect([...snapshot.rollups].sort((a, b) => (a.date < b.date ? -1 : 1))).toEqual(
      snapshot.rollups,
    );
    expect(snapshot.unreadableDates).toEqual([]);
    expect(snapshot.exportedAt).toBe("2026-11-30T06:00:00-05:00");
    expect(snapshot.problem).toBeNull();
    expect(warnings).toEqual([]);
  });

  it("reads the targets the days are judged against", async () => {
    const { folder } = fixtureFolder("full");
    const snapshot = await folder.snapshot();

    expect(snapshot.goalSettings?.targets.kcal).toBe(2_200);
    expect(snapshot.goalSettings?.targets.proteinMinG).toBe(140);
    expect(snapshot.goalSettings?.body.goalWeightKg).toBe(68);
  });

  it("keeps an unmeasured value null rather than zero", async () => {
    const { folder } = fixtureFolder("full");
    const snapshot = await folder.snapshot();
    const day = snapshot.byDate.get("2026-11-03")!;

    expect(day.body.bodyFatPct).toBeNull();
    expect(day.body.waistCm).toBeNull();
    expect(day.nutrition.kcal).toBe(2_050);
  });

  it("re-reads when the file on disk changes", async () => {
    const dir = await scratch(() => copyFixture("full"));
    const { folder } = folderAt(dir);
    expect((await folder.snapshot()).rollups).toHaveLength(28);

    const path = join(dir, "export.json");
    const whole = JSON.parse(await readFile(path, "utf8"));
    whole.rollups = whole.rollups.slice(0, 5);
    await writeFile(path, JSON.stringify(whole));

    expect((await folder.snapshot()).rollups).toHaveLength(5);
  });
});

describe("a folder with nothing in it", () => {
  it("reports no data rather than throwing", async () => {
    const dir = await scratch(emptyFolderDir);
    const { folder, warnings } = folderAt(dir);
    const snapshot = await folder.snapshot();

    expect(snapshot.rollups).toEqual([]);
    expect(snapshot.latest).toBeNull();
    expect(snapshot.goalSettings).toBeNull();
    expect(snapshot.problem).toContain("nothing has been exported");
    expect(warnings).toHaveLength(1);
  });
});

describe("a folder missing export.json", () => {
  it("reports no data, even with the markdown files present", async () => {
    const { folder } = fixtureFolder("missing-export");
    const snapshot = await folder.snapshot();

    expect(snapshot.rollups).toEqual([]);
    expect(snapshot.latest).toBeNull();
    expect(snapshot.problem).toContain("no export.json");
  });
});

describe("an export.json that is empty or half-written", () => {
  it("treats a zero-byte file as no data", async () => {
    const dir = await scratch(emptyFolderDir);
    await writeFile(join(dir, "export.json"), "");
    const { folder, warnings } = folderAt(dir);
    const snapshot = await folder.snapshot();

    expect(snapshot.rollups).toEqual([]);
    expect(snapshot.problem).toContain("is empty");
    expect(warnings[0]).toContain("is empty");
  });

  it("treats a truncated file as no data", async () => {
    const { folder, warnings } = fixtureFolder("partial");
    const snapshot = await folder.snapshot();

    expect(snapshot.rollups).toEqual([]);
    expect(snapshot.latest).toBeNull();
    expect(snapshot.problem).toContain("not valid JSON");
    expect(warnings[0]).toContain("partial file");
  });

  it("treats valid JSON that is not an export as no data", async () => {
    const dir = await scratch(emptyFolderDir);
    await writeFile(join(dir, "export.json"), JSON.stringify({ rollups: "soon" }));
    const { folder } = folderAt(dir);
    const snapshot = await folder.snapshot();

    expect(snapshot.rollups).toEqual([]);
    expect(snapshot.problem).toContain("not an Ascension export");
  });
});

describe("an export.json with malformed rows", () => {
  it("keeps the good days and names the bad ones", async () => {
    const { folder, warnings } = fixtureFolder("malformed");
    const snapshot = await folder.snapshot();

    // Four days in the file: two readable, one with a string where a number belongs,
    // one with a field the contract does not know. Plus an entry with no date at all.
    expect(snapshot.rollups.map((day) => day.date)).toEqual([
      "2026-11-03",
      "2026-11-06",
    ]);
    expect(snapshot.unreadableDates).toEqual(["2026-11-04", "2026-11-05"]);
    expect(snapshot.latest).toBe("2026-11-06");
    expect(warnings[0]).toContain("carry no date");
    expect(warnings[0]).toContain("do not satisfy the contract");
  });

  it("never lets a malformed measurement become a zero", async () => {
    const { folder } = fixtureFolder("malformed");
    const snapshot = await folder.snapshot();

    // The day whose `kcal` was the string "lots" is absent, not present with 0.
    expect(snapshot.byDate.has("2026-11-04")).toBe(false);
    for (const day of snapshot.rollups) {
      expect(typeof day.nutrition.kcal === "number" || day.nutrition.kcal === null).toBe(
        true,
      );
    }
  });

  it("ignores a broken CSV beside it — export.json is the superset", async () => {
    const { folder } = fixtureFolder("malformed");
    const snapshot = await folder.snapshot();
    expect(snapshot.rollups).toHaveLength(2);
    expect(snapshot.problem).not.toContain("csv");
  });
});

describe("a folder that is not there", () => {
  it("raises a configuration error naming the environment variable", async () => {
    const { folder } = folderAt("/nowhere/ascension-does-not-exist");
    await expect(folder.snapshot()).rejects.toThrow(ExportFolderUnavailable);
    await expect(folder.snapshot()).rejects.toThrow("ASCENSION_EXPORT_DIR");
  });

  it("raises when the path is a file rather than a folder", async () => {
    const dir = await scratch(emptyFolderDir);
    const path = join(dir, "not-a-folder");
    await writeFile(path, "");
    const { folder } = folderAt(path);
    await expect(folder.snapshot()).rejects.toThrow("not a directory");
  });
});

describe("a newer schemaVersion", () => {
  it("says so rather than silently reading it as the current one", async () => {
    const dir = await scratch(emptyFolderDir);
    await writeFile(
      join(dir, "export.json"),
      JSON.stringify({ schemaVersion: 99, rollups: [] }),
    );
    const { folder, warnings } = folderAt(dir);
    const snapshot = await folder.snapshot();

    expect(snapshot.problem).toContain("schemaVersion 99");
    expect(warnings[0]).toContain("this server reads 1");
  });
});
