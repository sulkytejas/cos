/**
 * Drain the events table once and exit. Used for "pnpm worker:once" to
 * smoke-test or to process a backlog before starting the long-running worker.
 *
 * Goes through the same atomic-claim + transactional-commit path as the
 * long-running worker (`queue.ts`), so a one-shot drain has identical
 * output-idempotency and crash-recovery semantics.
 */
import { recoverOnBoot, drainUntilEmpty } from "./queue";
import { sqlite_ } from "./db";

async function main() {
  console.log("[worker:once] draining pending events…");
  // Reclaim anything a prior crashed run left 'processing' so it drains too.
  recoverOnBoot();
  const n = await drainUntilEmpty();
  console.log(`[worker:once] done — processed ${n} event(s).`);
  sqlite_.close();
}

main().catch((err) => {
  console.error("[worker:once] fatal:", err);
  process.exit(1);
});
