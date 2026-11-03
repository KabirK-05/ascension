import { describe, expect, it } from "vitest";
import {
  addDays,
  daysBetween,
  enumerateDates,
  isoWeekStart,
  isoWeekday,
} from "../src/dates";

describe("calendar arithmetic", () => {
  it("adds and subtracts across a month and a year boundary", () => {
    expect(addDays("2026-11-03", 1)).toBe("2026-11-04");
    expect(addDays("2026-10-31", 1)).toBe("2026-11-01");
    expect(addDays("2026-01-01", -1)).toBe("2025-12-31");
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
  });

  it("is unaffected by the DST change, because these are calendar days", () => {
    // Toronto falls back on 2026-11-01.
    expect(addDays("2026-10-31", 2)).toBe("2026-11-02");
    expect(daysBetween("2026-10-31", "2026-11-02")).toBe(2);
  });

  it("numbers weekdays the ISO way, Monday = 1", () => {
    expect(isoWeekday("2026-11-02")).toBe(1);
    expect(isoWeekday("2026-11-03")).toBe(2);
    expect(isoWeekday("2026-11-08")).toBe(7);
  });

  it("starts a week on Monday", () => {
    expect(isoWeekStart("2026-11-03")).toBe("2026-11-02");
    expect(isoWeekStart("2026-11-08")).toBe("2026-11-02");
    expect(isoWeekStart("2026-11-09")).toBe("2026-11-09");
  });

  it("enumerates inclusively, and nothing for a reversed range", () => {
    expect(enumerateDates("2026-11-02", "2026-11-04")).toEqual([
      "2026-11-02",
      "2026-11-03",
      "2026-11-04",
    ]);
    expect(enumerateDates("2026-11-04", "2026-11-02")).toEqual([]);
  });
});
