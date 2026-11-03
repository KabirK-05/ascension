-- Seed the two documents docs/EXPORT_SCHEMA.md specifies in full, so a fresh
-- database can answer `get_today` with real targets. `program` is deliberately
-- NOT seeded: §2.2 shows only the `upperA` session, and inventing the rest here
-- would fork a contract the device owns.
--
-- INSERT OR IGNORE, so re-running never clobbers a document the device or Muse
-- has since written.

INSERT OR IGNORE INTO documents (key, version, json, updatedAt, updatedBy)
VALUES (
  'goalSettings',
  1,
  json('{
    "targets": {
      "kcal": 2200, "proteinG": 150, "proteinMinG": 140,
      "fatMinG": 60, "fatMaxG": 70, "steps": 10000, "sleepMinutes": 450
    },
    "body": { "goalWeightKg": 68.0, "heightCm": 170 },
    "programStartDate": "2026-11-03",
    "deloadEveryWeeks": 5,
    "timezone": "America/Toronto",
    "dietaryRules": {
      "excludedMeats": ["pork", "beef"],
      "allowedDairy": ["milk_bournvita"],
      "noLiquidCalories": true
    }
  }'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
  'system'
);

INSERT OR IGNORE INTO documents (key, version, json, updatedAt, updatedBy)
VALUES (
  'flags',
  1,
  json('{
    "remoteBridgeEnabled": true,
    "museWritesEnabled": true,
    "museWriteMode": "apply",
    "rawDetailSyncEnabled": false,
    "foundationModelsEnabled": true
  }'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
  'system'
);
