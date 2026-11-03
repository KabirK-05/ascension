import type { D1Migration } from "@cloudflare/vitest-plugin";
import { env } from "cloudflare:test";
import type { Env } from "../src/env";

/**
 * `cloudflare:test` types `env` as the bindings in `wrangler.toml` only. The
 * secrets and the migration list come from `vitest.config.ts`, which is why this
 * is asserted rather than inferred.
 */
export const testEnv = env as unknown as Env & {
  TEST_MIGRATIONS: D1Migration[];
};
