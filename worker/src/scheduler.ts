/**
 * Atlas worker — the scheduler (SERVER_ARCHITECTURE.md §4.c).
 *
 * Wall-clock timers, NOT `getHours()` polling:
 *   - a `setTimeout` to the next **06:00 local** for `daily_scan`, re-armed
 *     after each fire,
 *   - the same gate on **Sundays** for `forward_drift_scan`,
 *   - a **60s** sweep that enqueues `watcher_due` for due watchers,
 *   - a **15-min** connector poll.
 *
 * Scans ENQUEUE an event (they never call the agent directly) with a
 * `dedupeKey` — so the queue is the single execution path and the unique
 * partial index makes the scan exactly-once.
 *
 * **Catch-up (the headline overnight failure to avoid).** A bare `setTimeout`
 * silently misses its window on VM suspend, NTP jump, or a post-06:00 restart —
 * and the dedupeKey would then suppress a late attempt. So on boot AND on every
 * wakeup we run a catch-up: "if no `daily_scan` with `dedupeKey=daily_scan:<today>`
 * exists AND local time ≥ 06:00, enqueue it now." This makes the scan
 * exactly-once AND guaranteed-to-eventually-fire — it fails **open** (runs late),
 * never **closed** (skips silently).
 */
import { enqueue, dedupeKeyExists, db, schema } from "./queue";
import { and, eq, isNull } from "drizzle-orm";

const DAILY_SCAN_HOUR_LOCAL = 6; // 06:00 local
const SUNDAY = 0; // Date.getDay() === 0
const WATCHER_SWEEP_MS = 60_000;
const CONNECTOR_POLL_MS = 15 * 60 * 1000;

/** Local YYYY-MM-DD for a Date (the dedupe key's date component). */
function localDateKey(d = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function dailyScanKey(d = new Date()): string {
  return `daily_scan:${localDateKey(d)}`;
}
function forwardDriftKey(d = new Date()): string {
  return `forward_drift_scan:${localDateKey(d)}`;
}

/** ms from now until the next 06:00 local (today if it hasn't passed, else tomorrow). */
function msUntilNextDailyScan(now = new Date()): number {
  const target = new Date(now);
  target.setHours(DAILY_SCAN_HOUR_LOCAL, 0, 0, 0);
  if (target.getTime() <= now.getTime()) target.setDate(target.getDate() + 1);
  return target.getTime() - now.getTime();
}

// ─────────────────────────── catch-up (fail-open) ───────────────────────────

/**
 * The exactly-once + guaranteed-to-fire guard. Idempotent: safe to call on boot
 * and on every wakeup. Enqueues the daily scan (and Sunday's forward-drift scan)
 * iff local time is past 06:00 and today's scan hasn't been enqueued yet. The
 * `dedupeKey` + unique index make a concurrent timer-fire + catch-up collapse to
 * one row.
 */
export function runCatchUp(now = new Date()): void {
  if (now.getHours() < DAILY_SCAN_HOUR_LOCAL) return; // window hasn't opened today

  const dKey = dailyScanKey(now);
  if (!dedupeKeyExists(dKey)) {
    const id = enqueue("daily_scan", {}, dKey);
    if (id) console.log(`[scheduler] catch-up enqueued daily_scan (${dKey})`);
  }

  if (now.getDay() === SUNDAY) {
    const fKey = forwardDriftKey(now);
    if (!dedupeKeyExists(fKey)) {
      const id = enqueue("forward_drift_scan", {}, fKey);
      if (id) console.log(`[scheduler] catch-up enqueued forward_drift_scan (${fKey})`);
    }
  }
}

// ─────────────────────────── scheduled scans ───────────────────────────

function fireDailyScan(): void {
  const now = new Date();
  const dKey = dailyScanKey(now);
  const id = enqueue("daily_scan", {}, dKey);
  if (id) console.log(`[scheduler] enqueued daily_scan (${dKey})`);
  else console.log(`[scheduler] daily_scan already enqueued today (${dKey}), skipped`);

  // Sunday → also the weekly forward-drift scan.
  if (now.getDay() === SUNDAY) {
    const fKey = forwardDriftKey(now);
    const fid = enqueue("forward_drift_scan", {}, fKey);
    if (fid) console.log(`[scheduler] enqueued forward_drift_scan (${fKey})`);
  }
}

// ─────────────────────────── watcher sweep ───────────────────────────

/** Enqueue a `watcher_due` for every active watcher whose nextCheck has elapsed. */
export function sweepWatchers(): void {
  const now = new Date().toISOString();
  const due = db
    .select()
    .from(schema.watchers)
    // §4.d: skip tombstoned watchers.
    .where(and(eq(schema.watchers.status, "active"), isNull(schema.watchers.deletedAt)))
    .all()
    .filter((w) => w.nextCheck <= now);

  for (const w of due) {
    // Dedupe so a watcher already queued (pending/processing) isn't queued again
    // before the prior check reschedules it. One in-flight check per watcher.
    // The event is scoped to the watcher's owner so the run is attributed and
    // budgeted correctly (§4.d/§4.f).
    const key = `watcher_due:${w.id}:${w.nextCheck}`;
    const id = enqueue("watcher_due", { watcherId: w.id }, key, w.userId);
    if (id) console.log(`[scheduler] enqueued watcher_due for ${w.id}`);
  }
}

// ─────────────────────────── connector poll ───────────────────────────

async function pollConnectorsOnce(): Promise<void> {
  const { pollOnce: pollGmail } = await import("./connectors/gmail");
  const { pollOnce: pollCalendar } = await import("./connectors/calendar");
  const { pollOnce: pollDrive } = await import("./connectors/drive");
  // Connectors are independent; one failing must not block the others.
  const results = await Promise.allSettled([pollGmail(), pollCalendar(), pollDrive()]);
  for (const r of results) {
    if (r.status === "rejected") console.warn("[scheduler] connector poll failed:", r.reason);
  }
}

// ─────────────────────────── lifecycle ───────────────────────────

export interface SchedulerHandle {
  /** Run a wakeup catch-up (e.g. after the runtime detects the process resumed). */
  wakeup(): void;
  /** Stop all timers. */
  stop(): void;
}

/**
 * Start the scheduler. `isDraining()` lets it skip enqueues during shutdown.
 * Returns a handle with `wakeup()` (re-runs catch-up) and `stop()`.
 */
export function startScheduler(opts: { isDraining: () => boolean } = { isDraining: () => false }): SchedulerHandle {
  const { isDraining } = opts;
  let dailyTimer: ReturnType<typeof setTimeout> | null = null;
  let watcherTimer: ReturnType<typeof setInterval> | null = null;
  let connectorTimer: ReturnType<typeof setInterval> | null = null;

  // Boot catch-up — fail OPEN: if we restarted past 06:00, run the missed scan.
  runCatchUp();

  // Arm the wall-clock daily timer; re-arm after each fire (and guard against
  // an early-firing timer caused by a clock change by re-checking the delay).
  const armDaily = () => {
    const delay = msUntilNextDailyScan();
    dailyTimer = setTimeout(() => {
      // A coarse timer or a forward NTP jump could fire slightly early; only act
      // once we're actually at/after 06:00, otherwise just re-arm.
      const now = new Date();
      if (now.getHours() >= DAILY_SCAN_HOUR_LOCAL && !isDraining()) {
        fireDailyScan();
      }
      armDaily();
    }, delay);
    if (typeof dailyTimer.unref === "function") dailyTimer.unref();
    const mins = Math.round(delay / 60000);
    console.log(`[scheduler] next daily_scan armed in ~${mins} min`);
  };
  armDaily();

  // 60s watcher sweep.
  watcherTimer = setInterval(() => {
    if (!isDraining()) {
      try {
        sweepWatchers();
      } catch (err) {
        console.warn("[scheduler] watcher sweep failed:", err);
      }
    }
  }, WATCHER_SWEEP_MS);
  if (typeof watcherTimer.unref === "function") watcherTimer.unref();

  // 15-min connector poll. Fire one immediately on boot, then on the interval.
  const poll = () => {
    if (isDraining()) return;
    pollConnectorsOnce().catch((err) => console.warn("[scheduler] connector poll failed:", err));
  };
  poll();
  connectorTimer = setInterval(poll, CONNECTOR_POLL_MS);
  if (typeof connectorTimer.unref === "function") connectorTimer.unref();

  return {
    wakeup() {
      // On any resume, re-run the catch-up so a suspend-past-06:00 fires late.
      if (!isDraining()) runCatchUp();
    },
    stop() {
      if (dailyTimer) clearTimeout(dailyTimer);
      if (watcherTimer) clearInterval(watcherTimer);
      if (connectorTimer) clearInterval(connectorTimer);
      dailyTimer = watcherTimer = connectorTimer = null;
    },
  };
}
