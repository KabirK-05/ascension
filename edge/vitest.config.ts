import { fileURLToPath } from "node:url";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// The same SQL `wrangler d1 migrations apply` runs, applied to the test D1.
const migrations = await readD1Migrations(
  fileURLToPath(new URL("./migrations", import.meta.url)),
);

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.toml" },
      miniflare: {
        bindings: {
          TEST_MIGRATIONS: migrations,
          // Test values, not secrets. The real ones live in `wrangler secret`.
          DEVICE_TOKEN: "test-device-token",
          OWNER_PASSWORD: "test-owner-password",
        },
      },
    }),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
