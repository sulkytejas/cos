/**
 * Atlas worker — the runtime (SERVER_ARCHITECTURE.md §4.c).
 *
 * Boots the bounded pool (queue) + the scheduler, runs boot crash-recovery and
 * the 60s watchdog, and owns the drain loop. On `SIGTERM` it sets a draining
 * flag, awaits in-flight runs up to `SHUTDOWN_GRACE_MS=20000`, closes SQLite,
 * and `exit(0)` — pairing with systemd `Restart=always`, `TimeoutStopSec=25`.
 *
 * This is the worker entrypoint (`pnpm worker:dev` → `worker/src/index.ts`
 * re-exports `main` from here).
 */
import { sqlite_ } from "./db";
import {
  drainOnce,
  drainInteractiveOnce,
  recoverOnBoot,
  recoverStuck,
  inFlightCount,
  WORKER_CONCURRENCY,
  WATCHDOG_INTERVAL_MS,
} from "./queue";
import { startScheduler, type SchedulerHandle } from "./scheduler";
import { agentPrefix } from "./agent/loop";
import { assertCacheEnabled, prewarm } from "../../src/server/anthropic/gateway";

const DRAIN_INTERVAL_MS = Number(process.env.WORKER_DRAIN_INTERVAL_MS ?? 30_000);
/**
 * Poll cadence for the interactive lane. Tight, because a `capture_complete` /
 * `ai_ask` blocks an open HTTP long-poll (router timeout ~20s) — we want it
 * claimed within a beat of being enqueued, even while a background scan occupies
 * the main drain slot. Far cheaper than the background drain (an empty claim is
 * one indexed UPDATE … RETURNING that touches no rows).
 */
const INTERACTIVE_DRAIN_INTERVAL_MS = Number(
  process.env.WORKER_INTERACTIVE_DRAIN_INTERVAL_MS ?? 500,
);
const SHUTDOWN_GRACE_MS = Number(process.env.SHUTDOWN_GRACE_MS ?? 20_000);
/**
 * If the gap between two drain ticks exceeds this, the process was almost
 * certainly suspended (VM sleep / laptop close / debugger pause). Treat it as a
 * wakeup and re-run the scheduler's catch-up so a missed 06:00 fires late.
 */
const WAKEUP_GAP_MS = Math.max(DRAIN_INTERVAL_MS * 3, 90_000);

let draining = false;
const isDraining = () => draining;

/** Resolves on the next SIGTERM/SIGINT; used to interrupt the sleep between ticks. */
let signalled: (() => void) | null = null;
function interruptibleSleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    // NOT unref'd: this timer is the worker's heartbeat between drain ticks and
    // is what keeps the Node event loop alive (every other timer IS unref'd, so
    // without this the process would self-exit after the first drain).
    const t = setTimeout(resolve, ms);
    signalled = () => {
      clearTimeout(t);
      resolve();
    };
  });
}

export async function main(): Promise<void> {
  console.log("[runtime] Atlas worker starting…");
  console.log(
    `[runtime] concurrency=${WORKER_CONCURRENCY} drain=${DRAIN_INTERVAL_MS}ms interactive=${INTERACTIVE_DRAIN_INTERVAL_MS}ms`,
  );
  console.log(`[runtime] ANTHROPIC_API_KEY: ${process.env.ANTHROPIC_API_KEY ? "set" : "missing — stub mode"}`);

  // LAUNCH BLOCKER (§4.b): assert the agent prefix carries cache_control — a
  // Tier-1 12-turn loop re-billing the ~215-line system prompt as fresh ITPM
  // every turn is what trips the input limit. Fail at boot, not at 2am.
  const { system, tools } = agentPrefix();
  assertCacheEnabled(system, tools);
  console.log(`[runtime] agent prefix cache_control: OK (${tools.length} tools)`);
  // Prewarm the prompt cache so the first overnight turn is a hit, not a write.
  await prewarm(system, tools);

  // Boot crash-recovery: requeue/expire anything left 'processing' by a crashed
  // previous run before we start claiming new work.
  recoverOnBoot();

  // Watchdog: reclaim stuck rows on a 60s cadence (independent of the drain).
  const watchdog = setInterval(() => {
    try {
      recoverStuck();
    } catch (err) {
      console.warn("[runtime] watchdog sweep failed:", err);
    }
  }, WATCHDOG_INTERVAL_MS);
  if (typeof watchdog.unref === "function") watchdog.unref();

  // Scheduler: wall-clock scans + watcher sweep + connector poll + catch-up.
  const scheduler: SchedulerHandle = startScheduler({ isDraining });

  // Graceful shutdown.
  const shutdown = (sig: string) => {
    if (draining) return;
    draining = true;
    console.log(`[runtime] ${sig} received — draining (grace ${SHUTDOWN_GRACE_MS}ms)…`);
    scheduler.stop();
    signalled?.(); // break the sleep so the drain loop exits promptly
  };
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));

  // Interactive drain — its OWN fast loop, running concurrently with the
  // background loop below. Claims only `capture_complete`/`ai_ask` (disjoint
  // from the background claim), so a keystroke completion is picked up within a
  // beat even while a long `daily_scan` occupies the background slot. Its sleep
  // is short + unref'd; the background loop keeps the event loop alive.
  const interactiveLoop = (async () => {
    while (!draining) {
      try {
        await drainInteractiveOnce();
      } catch (err) {
        console.error("[runtime] interactive drain failed:", err);
      }
      if (draining) break;
      await new Promise<void>((resolve) => {
        const t = setTimeout(resolve, INTERACTIVE_DRAIN_INTERVAL_MS);
        if (typeof t.unref === "function") t.unref();
      });
    }
  })();

  // Drain loop — claim + run pending events, detect wakeups, sleep, repeat.
  let lastTick = Date.now();
  while (!draining) {
    try {
      // Drain everything currently pending (the bounded pool inside drainOnce
      // bounds concurrency; we loop until the claim returns nothing).
      while ((await drainOnce()) > 0 && !draining) {
        /* keep draining */
      }
    } catch (err) {
      console.error("[runtime] drain failed:", err);
    }

    if (draining) break;

    await interruptibleSleep(DRAIN_INTERVAL_MS);

    // Wakeup detection: a gap far larger than the drain interval means the
    // process was suspended (VM sleep / NTP jump). Re-run the scheduler's
    // catch-up so a 06:00 missed during the suspend fires late (fail open).
    const now = Date.now();
    const gap = now - lastTick;
    lastTick = now;
    if (gap > WAKEUP_GAP_MS && !draining) {
      console.warn(`[runtime] detected ${Math.round(gap / 1000)}s gap — treating as wakeup`);
      scheduler.wakeup();
    }
  }

  // Let the interactive loop observe `draining` and exit before we drain.
  await interactiveLoop;

  // ── Graceful drain ──
  await gracefulDrain();
  clearInterval(watchdog);
  closeDb();
  console.log("[runtime] shutdown complete. bye.");
  await flushStdio();
  process.exit(0);
}

/**
 * Flush stdout/stderr before `process.exit`. When stdout is a pipe (systemd
 * journal, a log file) `console.log` is async-buffered and a bare
 * `process.exit()` truncates the last lines — including the shutdown trace.
 */
function flushStdio(): Promise<void> {
  const flush = (s: NodeJS.WriteStream) =>
    new Promise<void>((resolve) => {
      // `write("")` resolves once the buffer is drained.
      if (s.writableLength === 0) return resolve();
      s.write("", () => resolve());
    });
  return Promise.all([flush(process.stdout), flush(process.stderr)]).then(() => undefined);
}

/** Wait for in-flight runs to finish, up to SHUTDOWN_GRACE_MS. */
async function gracefulDrain(): Promise<void> {
  const deadline = Date.now() + SHUTDOWN_GRACE_MS;
  let inFlight = inFlightCount();
  if (inFlight === 0) {
    console.log("[runtime] no in-flight runs; clean stop.");
    return;
  }
  console.log(`[runtime] waiting for ${inFlight} in-flight run(s)…`);
  while (Date.now() < deadline) {
    inFlight = inFlightCount();
    if (inFlight === 0) {
      console.log("[runtime] all in-flight runs drained.");
      return;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  inFlight = inFlightCount();
  if (inFlight > 0) {
    // Out of grace: the watchdog on the *next* boot will reclaim these rows
    // (they stay 'processing'); their transactional commit means no partial
    // output leaks. systemd will SIGKILL at TimeoutStopSec if we overstay.
    console.warn(`[runtime] grace expired with ${inFlight} run(s) still in-flight; they will be reclaimed on restart.`);
  }
}

function closeDb(): void {
  try {
    sqlite_.close();
  } catch (err) {
    console.warn("[runtime] error closing SQLite:", err);
  }
}
