-- ASC-13 — what the write half of Stream B needs beyond `documents` and
-- `mutations`, which 0001 already created.
--
-- Nothing here changes an existing field shape, so `schemaVersion` stays 1.

-- Open suggestions awaiting a one-tap accept (docs/MUSE_CAPABILITIES.md).
--
-- Two sources land in the same table. `device` rows are the §F6 calorie
-- auto-adjust the phone raised and handed up; `muse` rows are Tier-1 writes Muse
-- asked for while `flags.museWriteMode` was `propose`, which the Worker recorded
-- instead of making.
--
-- `actionKind`/`actionPayload` are what accepting *does*. They are NULL for a
-- suggestion only the phone can apply, in which case `accept_suggestion` queues
-- a mutation rather than writing a document here.
--
-- Append-and-decide, never deleted: there are no delete tools in v1, and the
-- decided rows are the audit trail of what was accepted and when.
CREATE TABLE suggestions (
  id             TEXT PRIMARY KEY,
  createdAt      TEXT NOT NULL,
  source         TEXT NOT NULL,
  kind           TEXT NOT NULL,
  text           TEXT NOT NULL,
  actionKind     TEXT,
  actionPayload  TEXT,
  status         TEXT NOT NULL DEFAULT 'pending',
  decidedAt      TEXT,
  CHECK (source IN ('muse', 'device')),
  CHECK (status IN ('pending', 'accepted')),
  CHECK ((actionKind IS NULL) = (actionPayload IS NULL))
);

CREATE INDEX suggestions_pending ON suggestions (createdAt) WHERE status = 'pending';

-- Where to send the silent `content-available` push that wakes the phone when a
-- Tier-2 mutation is queued (docs/TECH_STACK.md §2.4).
--
-- An APNs token, a random `deviceId` and a timestamp: no name, no email, nothing
-- that identifies a person (§2.6). Keyed on the token because APNs rotates them,
-- and a rotated token is a new row the old one is replaced by.
CREATE TABLE push_tokens (
  token        TEXT PRIMARY KEY,
  deviceId     TEXT NOT NULL,
  environment  TEXT NOT NULL,
  updatedAt    TEXT NOT NULL,
  CHECK (environment IN ('production', 'sandbox')),
  CHECK (length(token) BETWEEN 32 AND 200)
);

CREATE INDEX push_tokens_device ON push_tokens (deviceId);
