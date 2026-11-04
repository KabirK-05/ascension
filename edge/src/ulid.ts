/**
 * ULIDs for the `mutations` table: 26 characters of Crockford base32, 48 bits of
 * millisecond timestamp then 80 bits of randomness, so ordering is lexicographic
 * and the phone can drain with `WHERE id > ?` on a plain cursor
 * (docs/EXPORT_SCHEMA.md §3).
 *
 * Monotonic within a millisecond: two mutations appended in the same tick must
 * still sort in the order they were made, because the device applies them in
 * `id` order and Muse's second write may depend on her first.
 */

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const TIME_CHARS = 10;
const RANDOM_CHARS = 16;

let lastMs = -1;
let lastRandom: number[] = [];

function encodeTime(ms: number): string {
  let remaining = ms;
  const out = new Array<string>(TIME_CHARS);
  for (let i = TIME_CHARS - 1; i >= 0; i -= 1) {
    out[i] = ALPHABET[remaining % 32] as string;
    remaining = Math.floor(remaining / 32);
  }
  return out.join("");
}

function randomChars(): number[] {
  const bytes = crypto.getRandomValues(new Uint8Array(RANDOM_CHARS));
  return [...bytes].map((byte) => byte % 32);
}

/** Increment the base-32 random half, carrying left. */
function increment(chars: number[]): number[] {
  const next = [...chars];
  for (let i = next.length - 1; i >= 0; i -= 1) {
    const value = (next[i] as number) + 1;
    if (value < 32) {
      next[i] = value;
      return next;
    }
    next[i] = 0;
  }
  // Overflowed all 80 bits inside one millisecond, which cannot happen in
  // practice; a fresh draw is still ordered after the previous millisecond.
  return randomChars();
}

export function ulid(now: number = Date.now()): string {
  // A clock that went backwards must not produce an id that sorts before the
  // last one: keep the last timestamp and only move the random half.
  if (now <= lastMs) {
    lastRandom = increment(lastRandom);
  } else {
    lastMs = now;
    lastRandom = randomChars();
  }
  const random = lastRandom.map((value) => ALPHABET[value] as string).join("");
  return encodeTime(lastMs) + random;
}

const ULID_PATTERN = /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/;

export function isUlid(value: string): boolean {
  return ULID_PATTERN.test(value);
}
