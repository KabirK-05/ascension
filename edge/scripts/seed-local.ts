/**
 * Seed a local `wrangler dev` through the real `POST /v1/ingest`, using the
 * same fixtures the tests use. For hand-verification with the MCP Inspector.
 *
 *   npm run db:apply:local
 *   npm run dev            # in another shell
 *   node scripts/seed-local.ts
 *
 * Invented data only. Never point this at a deployed Worker.
 */
import { seedSeries } from "../test/fixtures";

const origin = process.env.ORIGIN ?? "http://localhost:8787";
const token = process.env.DEVICE_TOKEN;
if (!token) {
  console.error("set DEVICE_TOKEN to the value in your .dev.vars");
  process.exit(1);
}

const rollups = seedSeries();
for (let i = 0; i < rollups.length; i += 100) {
  const batch = rollups.slice(i, i + 100);
  const response = await fetch(`${origin}/v1/ingest`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ schemaVersion: 1, rollups: batch }),
  });
  const body = await response.text();
  console.log(response.status, body.slice(0, 160));
  if (!response.ok) process.exit(1);
}
