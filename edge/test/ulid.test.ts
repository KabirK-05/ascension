/**
 * The mutation id. The device applies the log in `id` order, so ordering is not
 * cosmetic: a pair of ids that sorts the wrong way applies Muse's second write
 * before her first.
 */
import { describe, expect, it } from "vitest";
import { isUlid, ulid } from "../src/ulid";

describe("ULID", () => {
  it("is 26 Crockford base32 characters", () => {
    const id = ulid();
    expect(id).toHaveLength(26);
    expect(isUlid(id)).toBe(true);
    // No I, L, O or U: the alphabet exists to be read aloud without ambiguity.
    expect(id).not.toMatch(/[ILOU]/);
  });

  it("sorts lexicographically by time", () => {
    const earlier = ulid(Date.UTC(2026, 10, 3));
    const later = ulid(Date.UTC(2026, 10, 4));
    expect(earlier < later).toBe(true);
  });

  it("stays monotonic inside one millisecond", () => {
    const now = Date.UTC(2026, 10, 3, 18, 0, 0);
    const ids = Array.from({ length: 200 }, () => ulid(now));
    expect(ids).toEqual([...ids].sort());
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("does not go backwards when the clock does", () => {
    const first = ulid(Date.UTC(2026, 10, 3, 18, 0, 1));
    const afterRewind = ulid(Date.UTC(2026, 10, 3, 17, 59, 59));
    expect(afterRewind > first).toBe(true);
  });

  it("rejects what is not a ULID", () => {
    expect(isUlid("")).toBe(false);
    expect(isUlid("yesterday")).toBe(false);
    expect(isUlid("01JC8X9Y2K3M4N5P6Q7R8S9T0")).toBe(false);
    expect(isUlid("01jc8x9y2k3m4n5p6q7r8s9t0v")).toBe(false);
    // 'I' is not in the alphabet.
    expect(isUlid("01IC8X9Y2K3M4N5P6Q7R8S9T0V")).toBe(false);
  });
});
