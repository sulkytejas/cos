/**
 * Drain the events table once and exit. Used for "pnpm worker:once" to
 * smoke-test or to process backlog before starting the long-running worker.
 */
import { db, schema } from "./db";
import { processEvent } from "./processors/event";
import { eq } from "drizzle-orm";

async function main() {
  console.log("[worker:once] draining pending events…");
  while (true) {
    const next = db
      .select()
      .from(schema.events)
      .where(eq(schema.events.status, "pending"))
      .limit(1)
      .all()[0];
    if (!next) break;

    db.update(schema.events).set({ status: "processing" }).where(eq(schema.events.id, next.id)).run();
    try {
      await processEvent(next);
      db.update(schema.events)
        .set({ status: "done", processedAt: new Date().toISOString() })
        .where(eq(schema.events.id, next.id))
        .run();
      console.log(`[worker:once] processed ${next.type}`);
    } catch (err) {
      db.update(schema.events)
        .set({ status: "failed", processedAt: new Date().toISOString(), error: (err as Error).message })
        .where(eq(schema.events.id, next.id))
        .run();
      console.error(`[worker:once] failed ${next.type}:`, err);
    }
  }
  console.log("[worker:once] done.");
}

main().catch((err) => {
  console.error("[worker:once] fatal:", err);
  process.exit(1);
});
