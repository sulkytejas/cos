/**
 * Atlas worker — the long-running process. Polls the events table, drains
 * pending events, then checks watchers and the daily scan window. Each
 * iteration is a clean snapshot; loose coupling all the way down.
 *
 * Run from the repo root:    pnpm worker:dev
 * One-shot drain (no loop):  pnpm worker:once
 */
import { db, schema } from "./db";
import { processEvent } from "./processors/event";
import { eq, lte } from "drizzle-orm";
import { randomUUID } from "node:crypto";

const POLL_INTERVAL_MS = 30_000;
const DAILY_SCAN_HOUR_LOCAL = 6;   // 06:00 local
const FORWARD_DRIFT_DAY = 0;       // Sunday = 0

let lastDailyScanDate: string | null = null;
let lastForwardDriftDate: string | null = null;

async function tick() {
  // 1) Drain pending events one at a time.
  const next = db
    .select()
    .from(schema.events)
    .where(eq(schema.events.status, "pending"))
    .limit(1)
    .all()[0];

  if (next) {
    db.update(schema.events).set({ status: "processing" }).where(eq(schema.events.id, next.id)).run();
    try {
      await processEvent(next);
      db.update(schema.events)
        .set({ status: "done", processedAt: new Date().toISOString() })
        .where(eq(schema.events.id, next.id))
        .run();
      console.log(`[worker] processed event ${next.id} (${next.type})`);
    } catch (err) {
      db.update(schema.events)
        .set({
          status: "failed",
          processedAt: new Date().toISOString(),
          error: (err as Error).message,
        })
        .where(eq(schema.events.id, next.id))
        .run();
      console.error(`[worker] event ${next.id} (${next.type}) failed:`, err);
    }
  }

  // 2) Watchers due
  const now = new Date().toISOString();
  const due = db
    .select()
    .from(schema.watchers)
    .where(eq(schema.watchers.status, "active"))
    .all()
    .filter((w) => w.nextCheck <= now);

  for (const w of due) {
    // Emit a watcher_due event rather than calling the agent here so the
    // same code path serves manual + scheduled watcher checks.
    db.insert(schema.events)
      .values({
        id: randomUUID(),
        type: "watcher_due",
        payload: { watcherId: w.id },
      })
      .run();
  }

  // 3) Daily scan window — fire once per day at the configured hour
  const today = new Date();
  const todayKey = today.toISOString().slice(0, 10);
  if (
    today.getHours() === DAILY_SCAN_HOUR_LOCAL &&
    lastDailyScanDate !== todayKey
  ) {
    lastDailyScanDate = todayKey;
    db.insert(schema.events)
      .values({ id: randomUUID(), type: "daily_scan", payload: {} })
      .run();
    console.log("[worker] queued daily_scan");
  }

  // 4) Forward-drift scan — Sundays at the same hour
  if (
    today.getDay() === FORWARD_DRIFT_DAY &&
    today.getHours() === DAILY_SCAN_HOUR_LOCAL &&
    lastForwardDriftDate !== todayKey
  ) {
    lastForwardDriftDate = todayKey;
    db.insert(schema.events)
      .values({ id: randomUUID(), type: "forward_drift_scan", payload: {} })
      .run();
    console.log("[worker] queued forward_drift_scan");
  }
}

async function pollConnectorsOnce() {
  const { pollOnce: pollGmail } = await import("./connectors/gmail");
  const { pollOnce: pollCalendar } = await import("./connectors/calendar");
  const { pollOnce: pollDrive } = await import("./connectors/drive");
  await Promise.all([pollGmail(), pollCalendar(), pollDrive()]);
}

let connectorsLastPoll = 0;
const CONNECTOR_POLL_INTERVAL_MS = 15 * 60 * 1000;

async function main() {
  console.log("[worker] Atlas worker starting…");
  console.log(`[worker] poll interval: ${POLL_INTERVAL_MS}ms`);
  console.log(`[worker] daily scan at: ${DAILY_SCAN_HOUR_LOCAL}:00 local`);
  console.log(`[worker] ANTHROPIC_API_KEY: ${process.env.ANTHROPIC_API_KEY ? "set" : "missing — stub mode"}`);

  // Initial connector poll on startup
  try {
    await pollConnectorsOnce();
    connectorsLastPoll = Date.now();
  } catch (err) {
    console.warn("[worker] initial connector poll failed:", err);
  }

  while (true) {
    try {
      await tick();
      if (Date.now() - connectorsLastPoll > CONNECTOR_POLL_INTERVAL_MS) {
        await pollConnectorsOnce();
        connectorsLastPoll = Date.now();
      }
    } catch (err) {
      console.error("[worker] tick failed:", err);
    }
    await sleep(POLL_INTERVAL_MS);
  }
}

function sleep(ms: number) {
  return new Promise<void>((res) => setTimeout(res, ms));
}

main().catch((err) => {
  console.error("[worker] fatal:", err);
  process.exit(1);
});
