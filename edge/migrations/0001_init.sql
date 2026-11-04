-- ASC-4 — the two streams of docs/TECH_STACK.md §2.3.
--
-- Stream A (observed, phone -> cloud, one-way) is `rollups`.
-- Stream B (intent, cloud <-> phone, two-way) is `documents` + `mutations`.

-- One DayRollup per day. `json` holds the whole validated object exactly as
-- docs/EXPORT_SCHEMA.md §1 defines it, so field names live in one place and
-- cannot drift from the app. `date` is the key, and ingest upserts on it, so the
-- phone re-sending a day is always safe. `timezone` and `updatedAt` are promoted
-- out of the body only because they are envelope facts the reads sort and report
-- on; every other field is read out of `json`.
CREATE TABLE rollups (
  date        TEXT PRIMARY KEY,
  timezone    TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  json        TEXT NOT NULL,
  ingestedAt  TEXT NOT NULL,
  CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')
);

-- The three mutable documents Muse may write (ASC-13). `version` increments on
-- every write and is the `If-Match` concurrency token. The body in `json` does
-- NOT repeat `version`, `updatedAt` or `updatedBy` -- those are these columns,
-- and the full document is composed from both halves on read.
CREATE TABLE documents (
  key        TEXT PRIMARY KEY,
  version    INTEGER NOT NULL,
  json       TEXT NOT NULL,
  updatedAt  TEXT NOT NULL,
  updatedBy  TEXT NOT NULL,
  CHECK (key IN ('goalSettings', 'program', 'flags')),
  CHECK (updatedBy IN ('muse', 'device', 'system')),
  CHECK (version >= 1)
);

-- Append-only write log: every change Muse ever makes, with an actor and a
-- timestamp. `id` is a ULID (26 chars, Crockford base32), so ordering is
-- lexicographic and the phone can drain with `WHERE id > ?` on a plain cursor.
-- `appliedAt` is set by the device for Tier-2 mutations, by the Worker for
-- Tier-1. No UPDATE of `payload` and no DELETE, ever.
CREATE TABLE mutations (
  id             TEXT PRIMARY KEY,
  createdAt      TEXT NOT NULL,
  actor          TEXT NOT NULL,
  kind           TEXT NOT NULL,
  payload        TEXT NOT NULL,
  appliedAt      TEXT,
  appliedResult  TEXT,
  CHECK (actor IN ('muse', 'device', 'system')),
  CHECK (length(id) = 26)
);

-- The phone's drain query: the unapplied tail, in ULID order.
CREATE INDEX mutations_unapplied ON mutations (id) WHERE appliedAt IS NULL;
