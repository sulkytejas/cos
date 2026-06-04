/**
 * Atlas worker — entrypoint.
 *
 * The body that used to live here is split into three modules per
 * SERVER_ARCHITECTURE.md §4.c:
 *   - `queue.ts`     — atomic claim + bounded pool + output-idempotency + watchdog
 *   - `scheduler.ts` — wall-clock scans + watcher sweep + connector poll + catch-up
 *   - `runtime.ts`   — boot + graceful SIGTERM drain (owns the drain loop)
 *
 * Run from the repo root:    pnpm worker:dev
 * One-shot drain (no loop):  pnpm worker:once
 */
import { main } from "./runtime";

main().catch((err) => {
  console.error("[worker] fatal:", err);
  process.exit(1);
});
