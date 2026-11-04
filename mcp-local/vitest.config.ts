import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Fixture folders are read from disk, and one test generates a multi-megabyte
    // `daily-log.md`, so these are not sub-millisecond unit tests.
    testTimeout: 30_000,
  },
});
