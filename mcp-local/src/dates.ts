/**
 * Calendar arithmetic on `YYYY-MM-DD` strings. Rollup dates are already in the
 * user's timezone (docs/EXPORT_SCHEMA.md), so these must never consult a clock
 * or a locale -- they walk the proleptic Gregorian calendar through UTC epoch
 * days and nothing else.
 */

const DAY_MS = 86_400_000;

function toEpochDay(date: string): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!match) throw new Error(`not a YYYY-MM-DD date: ${date}`);
  const [, y, m, d] = match as unknown as [string, string, string, string];
  return Date.UTC(Number(y), Number(m) - 1, Number(d)) / DAY_MS;
}

function fromEpochDay(epochDay: number): string {
  return new Date(epochDay * DAY_MS).toISOString().slice(0, 10);
}

export function addDays(date: string, days: number): string {
  return fromEpochDay(toEpochDay(date) + days);
}

/** Whole days from `from` to `to`; negative when `to` precedes `from`. */
export function daysBetween(from: string, to: string): number {
  return toEpochDay(to) - toEpochDay(from);
}

export function compareDates(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Every date from `from` to `to`, inclusive. Empty when `to` precedes `from`. */
export function enumerateDates(from: string, to: string): string[] {
  const span = daysBetween(from, to);
  if (span < 0) return [];
  return Array.from({ length: span + 1 }, (_, i) => addDays(from, i));
}

/**
 * The Monday of the ISO week containing `date`. ISO-8601 weekdays run Monday = 1
 * to Sunday = 7, which is what `program.days[].weekday` means.
 */
export function isoWeekStart(date: string): string {
  return addDays(date, -(isoWeekday(date) - 1));
}

/** Monday = 1 … Sunday = 7. */
export function isoWeekday(date: string): number {
  const sundayFirst = new Date(toEpochDay(date) * DAY_MS).getUTCDay();
  return sundayFirst === 0 ? 7 : sundayFirst;
}
