/**
 * Atlas worker — the event queue (SERVER_ARCHITECTURE.md §4.c).
 *
 * Responsibilities:
 *   - **Atomic claim.** `UPDATE events SET status='processing', claimedAt, attempts+1
 *     WHERE id IN (SELECT … pending ORDER BY createdAt LIMIT :batch) RETURNING *`,
 *     so two worker instances (or an old + new during a rolling restart) can
 *     never claim the same row.
 *   - **Bounded pool.** Claimed events run through a pool of size
 *     `WORKER_CONCURRENCY` (default **1** — SQLite is single-writer, so write
 *     concurrency is illusory throughput; the gateway's *network* concurrency
 *     is what matters, and the per-tick cap=2 rate hack is gone — rate-limiting
 *     lives in the gateway).
 *   - **Output-idempotency.** `claim → (await agent) → persist → markDone →
 *     signals.processed` — the persist + mark run in ONE better-sqlite3
 *     transaction AFTER the await returns; a crash rolls back the writes and the
 *     event cleanly requeues. Recovery deletes a requeued event's prior output
 *     (`generatedByEventId`) before re-running, so kill -9 mid-`daily_scan`
 *     produces no duplicate briefs.
 *   - **Watchdog / crash recovery.** On boot and every 60s, requeue `processing`
 *     rows whose `claimedAt < now - STUCK_MS` (attempts<MAX_ATTEMPTS → pending,
 *     else failed). The running agent heartbeats `claimedAt` so a slow-but-alive
 *     Tier-1 run (≈8–10 min) is never reclaimed and re-run concurrently.
 *   - **Fail-fast on non-transient errors** (JSON parse / validation) instead of
 *     burning 3 full agent re-runs; retries are reserved for transient failures.
 */
import type Database from "better-sqlite3";
import { sqlite_, db, schema } from "./db";
import { prepareEvent, type EventCommit } from "./processors/event";
import {
  NonTransientAgentError,
  TransientAgentError,
} from "../../src/server/anthropic/gateway";
import { eq, sql } from "drizzle-orm";

// ─────────────────────────── tunables (§4.c) ───────────────────────────

/** Writes are single-writer in SQLite — 1 is correct, not a bottleneck. */
export const WORKER_CONCURRENCY = Math.max(1, Number(process.env.WORKER_CONCURRENCY ?? 1));
/** Rows claimed per drain pass. */
const CLAIM_BATCH = Math.max(1, Number(process.env.WORKER_CLAIM_BATCH ?? WORKER_CONCURRENCY));
/** Retry ceiling for transient failures (429/5xx/crash). */
const MAX_ATTEMPTS = Math.max(1, Number(process.env.WORKER_MAX_ATTEMPTS ?? 3));
/**
 * A claim older than this with no heartbeat is considered dead and reclaimed.
 * Set ABOVE the worst-case throttled agent wall-clock (a Tier-1 12-turn run
 * with bucket waits can legitimately take ~8–10 min) — the heartbeat keeps a
 * live run fresh, so only a truly crashed run trips this.
 */
const STUCK_MS = Math.max(60_000, Number(process.env.WORKER_STUCK_MS ?? 15 * 60 * 1000));
/** How often the in-flight event bumps its own claimedAt while running. */
const HEARTBEAT_MS = Math.max(5_000, Number(process.env.WORKER_HEARTBEAT_MS ?? 30_000));
/** Watchdog sweep cadence. */
export const WATCHDOG_INTERVAL_MS = 60_000;

const raw: Database.Database = sqlite_;

// ─────────────────────────── interactive vs background lanes ───────────────────────────

/**
 * Latency-sensitive, user-blocking jobs. These are claimed by a SEPARATE drain
 * lane (`drainInteractiveOnce`) that runs CONCURRENTLY with the background lane,
 * so a `capture_complete`/`ai_ask` enqueued mid-`daily_scan` is claimed + run at
 * once instead of waiting out an 8–10 min Tier-1 scan behind the single
 * `WORKER_CONCURRENCY` drain slot. The two lanes claim DISJOINT type sets (the
 * background claim excludes these), so they can never claim the same row even
 * though both write `status='processing'`.
 *
 * Kept short — only the keystroke/poll-blocking surfaces qualify. `daily_scan`,
 * drift, watcher sweeps, signal coalescing are background and ride the main lane.
 */
const INTERACTIVE_TYPES = ["capture_complete", "ai_ask"] as const;
// A SQL list literal — `'capture_complete','ai_ask'` — for the IN (...) clauses.
const INTERACTIVE_SQL_LIST = INTERACTIVE_TYPES.map((t) => `'${t}'`).join(", ");

// ─────────────────────────── prepared statements ───────────────────────────

/**
 * Atomic multi-row claim for the BACKGROUND lane. better-sqlite3 supports
 * `UPDATE … RETURNING`, so we flip status to 'processing', stamp claimedAt + bump
 * attempts, and read the claimed rows back in a single statement (one writer, no
 * claim race). Interactive types are EXCLUDED here — the interactive lane owns
 * them — so the two lanes are disjoint and never double-claim a row.
 */
const claimStmt = raw.prepare(`
  UPDATE events
     SET status = 'processing',
         claimed_at = @now,
         updated_at = @now,
         attempts = attempts + 1
   WHERE id IN (
           SELECT id FROM events
            WHERE status = 'pending'
              AND type NOT IN (${INTERACTIVE_SQL_LIST})
            ORDER BY created_at, id
            LIMIT @batch
         )
  RETURNING *
`);

/**
 * Atomic claim for the INTERACTIVE lane — same shape, but restricted to the
 * interactive types. Runs on its own concurrent drain so user-blocking jobs are
 * never starved behind a background scan occupying the single background slot.
 */
const claimInteractiveStmt = raw.prepare(`
  UPDATE events
     SET status = 'processing',
         claimed_at = @now,
         updated_at = @now,
         attempts = attempts + 1
   WHERE id IN (
           SELECT id FROM events
            WHERE status = 'pending'
              AND type IN (${INTERACTIVE_SQL_LIST})
            ORDER BY created_at, id
            LIMIT @batch
         )
  RETURNING *
`);

const heartbeatStmt = raw.prepare(`UPDATE events SET claimed_at = @now WHERE id = @id`);

/** Reclaim/expire stuck rows. Two passes so we can split below/above MAX_ATTEMPTS. */
const recoverToPendingStmt = raw.prepare(`
  UPDATE events
     SET status = 'pending', claimed_at = NULL, updated_at = @now
   WHERE status = 'processing'
     AND claimed_at IS NOT NULL
     AND claimed_at < @cutoff
     AND attempts < @maxAttempts
`);
const recoverToFailedStmt = raw.prepare(`
  UPDATE events
     SET status = 'failed', claimed_at = NULL,
         processed_at = @now,
         updated_at = @now,
         error = COALESCE(error, 'stuck: exceeded max attempts after reclaim')
   WHERE status = 'processing'
     AND claimed_at IS NOT NULL
     AND claimed_at < @cutoff
     AND attempts >= @maxAttempts
`);

// ─────────────────────────── DB column shape ───────────────────────────
// The raw RETURNING row uses snake_case column names. We only need a few fields
// off it to build the Drizzle `Event` the processors expect.
interface RawEventRow {
  id: string;
  user_id: string;
  type: schema.Event["type"];
  payload: string;
  status: schema.Event["status"];
  claimed_at: string | null;
  attempts: number;
  dedupe_key: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  processed_at: string | null;
  error: string | null;
  /** JSON job result (ai_ask/capture write here in the commit txn). */
  result: string | null;
}

function toEvent(row: RawEventRow): schema.Event {
  return {
    id: row.id,
    userId: row.user_id,
    type: row.type,
    payload: JSON.parse(row.payload),
    status: row.status,
    claimedAt: row.claimed_at,
    attempts: row.attempts,
    dedupeKey: row.dedupe_key,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    processedAt: row.processed_at,
    error: row.error,
    // The claim happens before the commit phase ever writes a result, so this is
    // null here; processors set it via writeEventResult inside the commit txn.
    result: row.result != null ? JSON.parse(row.result) : null,
  };
}

// ─────────────────────────── enqueue (with dedupe) ───────────────────────────

/**
 * Enqueue an event. When `dedupeKey` is supplied the insert is collapsed against
 * the unique partial index — so a concurrent boot + timer + catch-up for
 * `daily_scan:<today>` produce exactly one LIVE row. Returns the row id if it was
 * inserted (or a prior failed attempt was reclaimed), or `null` if a still-live
 * (pending/processing/done) dedupe match suppressed it.
 *
 * §4.c (catch-up must fail OPEN): a plain `DO NOTHING` would also collapse against
 * a `failed` row that kept its `dedupe_key`, so a non-transiently-failed
 * `daily_scan` could NEVER be re-enqueued that day — `dedupeKeyExists()` excludes
 * 'failed' and would wave the catch-up through, but the insert would silently
 * no-op (skip CLOSED). Instead, on conflict we RECLAIM a `failed` row back to a
 * fresh pending attempt (and leave live rows untouched), so the scan is still
 * exactly-once for live work yet guaranteed to eventually fire.
 */
// The conflict target restates the partial index's WHERE predicate so SQLite
// matches it to `events_dedupe_key_unq` (a partial unique index). The `setWhere`
// restricts the reclaim to a previously-FAILED row — a live row is left alone, so
// concurrent boot/timer/catch-up still collapse to the one in-flight row.
const insertEventStmt = raw.prepare(`
  INSERT INTO events (id, user_id, type, payload, status, attempts, dedupe_key, updated_at)
  VALUES (@id, @userId, @type, @payload, 'pending', 0, @dedupeKey, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO UPDATE SET
       status       = 'pending',
       payload      = excluded.payload,
       user_id      = excluded.user_id,
       attempts     = 0,
       claimed_at   = NULL,
       processed_at = NULL,
       error        = NULL,
       updated_at   = strftime('%Y-%m-%dT%H:%M:%fZ','now')
     WHERE events.status = 'failed'
  RETURNING id
`);

/**
 * Enqueue an event scoped to `userId` (§4.d/§4.f). Scheduler scans
 * (daily/drift) pass the single-tenant bootstrap operator; the watcher sweep
 * and signal coalescing pass the OWNER of the watcher/signal so the worker run
 * is charged and scoped correctly. Defaults to the bootstrap operator.
 */
export function enqueue(
  type: schema.Event["type"],
  payload: unknown,
  dedupeKey?: string,
  userId: string = schema.BOOTSTRAP_USER_ID,
): string | null {
  const id = crypto.randomUUID();
  const res = insertEventStmt.get({
    id,
    userId,
    type,
    payload: JSON.stringify(payload ?? {}),
    dedupeKey: dedupeKey ?? null,
  }) as { id: string } | undefined;
  return res?.id ?? null;
}

/** True iff a non-failed event already exists for this dedupeKey. */
const dedupeExistsStmt = raw.prepare(`
  SELECT 1 FROM events
   WHERE dedupe_key = @dedupeKey
     AND status IN ('pending','processing','done')
   LIMIT 1
`);
export function dedupeKeyExists(dedupeKey: string): boolean {
  return !!dedupeExistsStmt.get({ dedupeKey });
}

// ─────────────────────────── error classification ───────────────────────────

/**
 * Non-transient errors (bad JSON, schema validation, programmer error) won't
 * heal on retry — fail immediately rather than burning MAX_ATTEMPTS full agent
 * re-runs. Transient errors (429/5xx/network/crash) are retried.
 *
 * The gateway's agent loop classifies its own failures as typed errors
 * (`NonTransientAgentError` / `TransientAgentError`) — honor those first so a
 * `TransientAgentError` ("agent send failed: …") is NEVER misread as fatal by
 * the message regex, and an "exceeded max turns" non-transient (which the regex
 * wouldn't otherwise match) still fails fast. Fall back to the message regex for
 * errors thrown deeper (e.g. a Zod validation in the commit txn).
 */
function isNonTransient(err: unknown): boolean {
  if (err instanceof TransientAgentError || (err as Error)?.name === "TransientAgentError") {
    return false;
  }
  if (err instanceof NonTransientAgentError || (err as Error)?.name === "NonTransientAgentError") {
    return true;
  }
  const msg = (err as Error)?.message ?? String(err);
  return /json|parse|unexpected token|validation|invalid|zod|schema/i.test(msg);
}

// ─────────────────────────── recovery ───────────────────────────

/**
 * Delete a requeued event's prior output before re-running it. The output-layer
 * idempotency guard: a `daily_scan` that wrote N briefs then crashed before
 * markDone is requeued — without this it would write N more on the retry.
 *
 * §4.c (output-idempotency): the prior output is not only the briefs + proposals
 * (keyed by `generatedByEventId`) but ALSO the canonical rows an auto-FILED
 * high-confidence proposal wrote (`persist.ts` files todos/decisions/entries
 * immediately for confidence ≥ 0.85). Those canonical rows carry no
 * `generatedByEventId`, and a re-run mints a FRESH `sourceProposalId`, so the
 * `sourceProposalId` unique guard wouldn't catch them — they'd silently double.
 * They DO carry `sourceBriefId` (the prior brief), so we delete them by the set
 * of prior brief ids this event produced, BEFORE deleting those briefs.
 */
const priorBriefIdsStmt = raw.prepare(
  `SELECT id FROM briefs WHERE generated_by_event_id = @id`,
);
const deleteBriefsStmt = raw.prepare(`DELETE FROM briefs WHERE generated_by_event_id = @id`);
const deleteProposalsStmt = raw.prepare(`DELETE FROM proposals WHERE generated_by_event_id = @id`);
const deleteTodosBySourceBrief = raw.prepare(`DELETE FROM todos WHERE source_brief_id = @briefId`);
const deleteDecisionsBySourceBrief = raw.prepare(`DELETE FROM decisions WHERE source_brief_id = @briefId`);
const deleteEntriesBySourceBrief = raw.prepare(`DELETE FROM entries WHERE source_brief_id = @briefId`);
function deletePriorOutput(eventId: string): void {
  // Auto-filed canonical rows first — keyed by the prior briefs' ids (captured
  // before the briefs are deleted), so an auto-file re-run can't double a todo.
  const priorBriefs = priorBriefIdsStmt.all({ id: eventId }) as Array<{ id: string }>;
  for (const { id: briefId } of priorBriefs) {
    deleteTodosBySourceBrief.run({ briefId });
    deleteDecisionsBySourceBrief.run({ briefId });
    deleteEntriesBySourceBrief.run({ briefId });
  }
  // Proposals next — they FK-reference briefs (onDelete: set null), but
  // deleting them first keeps the intent obvious.
  deleteProposalsStmt.run({ id: eventId });
  deleteBriefsStmt.run({ id: eventId });
}

// ─────────────────────────── per-event run ───────────────────────────

const markDoneStmt = raw.prepare(
  `UPDATE events SET status='done', processed_at=@now, updated_at=@now, claimed_at=NULL WHERE id=@id`,
);
const markFailedStmt = raw.prepare(
  `UPDATE events SET status=@status, processed_at=@now, updated_at=@now, claimed_at=NULL, error=@error WHERE id=@id`,
);

/**
 * Process one already-claimed event end-to-end:
 *   1. delete any prior output of this event (idempotent re-run),
 *   2. heartbeat claimedAt while the agent runs,
 *   3. run the agent (the await — NO db writes),
 *   4. in ONE txn: run the commit (persist + post-effects) + markDone.
 *
 * On a transient failure with attempts left, requeue to pending; otherwise mark
 * failed. The whole step is crash-safe: a crash before step 4's txn commits
 * leaves the row 'processing' for the watchdog to reclaim.
 */
async function runClaimedEvent(event: schema.Event): Promise<void> {
  // (1) Clear prior output so a retry can't double it.
  deletePriorOutput(event.id);

  // (2) Heartbeat keeps a long-but-alive run from being reclaimed.
  const hb = setInterval(() => {
    try {
      heartbeatStmt.run({ id: event.id, now: new Date().toISOString() });
    } catch {
      /* a transient busy is fine; next beat retries */
    }
  }, HEARTBEAT_MS);
  if (typeof hb.unref === "function") hb.unref();

  let commit: EventCommit;
  try {
    // (3) The await. Agent run + context reads only; no persistence yet.
    commit = await prepareEvent(event);
  } catch (err) {
    clearInterval(hb);
    return handleFailure(event, err);
  }
  clearInterval(hb);

  try {
    // (4) One transaction: persist + post-effects + markDone. A crash here
    // rolls back everything and leaves the row 'processing' → watchdog requeues.
    raw.transaction(() => {
      commit(event.id);
      markDoneStmt.run({ id: event.id, now: new Date().toISOString() });
    })();
    console.log(`[queue] processed event ${event.id} (${event.type})`);
  } catch (err) {
    handleFailure(event, err);
  }
}

function handleFailure(event: schema.Event, err: unknown): void {
  const message = (err as Error)?.message ?? String(err);
  // Best-effort: don't leave half-written output from a failed commit.
  try {
    deletePriorOutput(event.id);
  } catch {
    /* ignore */
  }
  const fatal = isNonTransient(err) || event.attempts >= MAX_ATTEMPTS;
  const now = new Date().toISOString();
  if (fatal) {
    markFailedStmt.run({ id: event.id, status: "failed", now, error: message });
    console.error(
      `[queue] event ${event.id} (${event.type}) FAILED (${isNonTransient(err) ? "non-transient" : "max attempts"}):`,
      message,
    );
  } else {
    // Transient + attempts remain → back to pending for another try.
    markFailedStmt.run({ id: event.id, status: "pending", now, error: message });
    console.warn(
      `[queue] event ${event.id} (${event.type}) transient failure, requeued (attempt ${event.attempts}/${MAX_ATTEMPTS}):`,
      message,
    );
  }
}

// ─────────────────────────── drain (bounded pool) ───────────────────────────

/** Run a freshly-claimed batch through a bounded pool. Returns rows processed. */
async function runBatch(rows: RawEventRow[]): Promise<number> {
  if (rows.length === 0) return 0;
  const events = rows.map(toEvent);
  let cursor = 0;
  async function worker(): Promise<void> {
    while (cursor < events.length) {
      const ev = events[cursor++];
      await runClaimedEvent(ev);
    }
  }
  const lanes = Array.from({ length: Math.min(WORKER_CONCURRENCY, events.length) }, () => worker());
  await Promise.all(lanes);
  return events.length;
}

/**
 * Claim up to CLAIM_BATCH pending BACKGROUND events and run them through a pool
 * of size WORKER_CONCURRENCY. Returns the number of events processed this pass.
 * Interactive jobs are drained by `drainInteractiveOnce` on a separate lane.
 */
export async function drainOnce(): Promise<number> {
  const rows = claimStmt.all({ now: new Date().toISOString(), batch: CLAIM_BATCH }) as RawEventRow[];
  return runBatch(rows);
}

/**
 * Claim + run pending INTERACTIVE events (`capture_complete`/`ai_ask`). Drains
 * the whole interactive backlog each call so a burst of keystroke completions
 * clears promptly. Runs concurrently with the background drain (disjoint claim
 * sets), so an interactive job never waits behind a long scan.
 */
export async function drainInteractiveOnce(): Promise<number> {
  let total = 0;
  for (;;) {
    const rows = claimInteractiveStmt.all({
      now: new Date().toISOString(),
      batch: CLAIM_BATCH,
    }) as RawEventRow[];
    const n = await runBatch(rows);
    if (n === 0) break;
    total += n;
  }
  return total;
}

/**
 * Drain repeatedly until BOTH lanes are empty (used by once.ts and catch-up).
 * Interactive jobs run first each pass so a one-shot drain still settles the
 * latency-sensitive work ahead of the background backlog.
 */
export async function drainUntilEmpty(): Promise<number> {
  let total = 0;
  for (;;) {
    const n = (await drainInteractiveOnce()) + (await drainOnce());
    if (n === 0) break;
    total += n;
  }
  return total;
}

// ─────────────────────────── watchdog ───────────────────────────

/**
 * Reclaim stuck `processing` rows. Run on boot and every WATCHDOG_INTERVAL_MS.
 * Returns { requeued, failed } counts.
 */
export function recoverStuck(): { requeued: number; failed: number } {
  const now = new Date().toISOString();
  const cutoff = new Date(Date.now() - STUCK_MS).toISOString();
  // Expire the exhausted ones first so the requeue pass doesn't touch them.
  const failed = recoverToFailedStmt.run({ cutoff, maxAttempts: MAX_ATTEMPTS, now }).changes;
  const requeued = recoverToPendingStmt.run({ cutoff, maxAttempts: MAX_ATTEMPTS, now }).changes;
  if (requeued || failed) {
    console.warn(`[queue] watchdog: requeued ${requeued} stuck, failed ${failed} exhausted`);
  }
  return { requeued, failed };
}

/**
 * Boot recovery: anything left `processing` from a previous (crashed) run is
 * orphaned — no heartbeat will ever refresh it. Reclaim immediately rather than
 * waiting out STUCK_MS, so a fast restart resumes the backlog at once.
 */
export function recoverOnBoot(): void {
  const now = new Date().toISOString();
  // Requeue every orphan with attempts left; expire the rest.
  const failed = raw
    .prepare(
      `UPDATE events SET status='failed', claimed_at=NULL, processed_at=@now, updated_at=@now,
              error=COALESCE(error,'orphaned at boot: exceeded max attempts')
        WHERE status='processing' AND attempts >= @maxAttempts`,
    )
    .run({ now, maxAttempts: MAX_ATTEMPTS }).changes;
  const requeued = raw
    .prepare(
      `UPDATE events SET status='pending', claimed_at=NULL, updated_at=@now
        WHERE status='processing' AND attempts < @maxAttempts`,
    )
    .run({ now, maxAttempts: MAX_ATTEMPTS }).changes;
  if (requeued || failed) {
    console.warn(`[queue] boot recovery: requeued ${requeued} orphaned, failed ${failed} exhausted`);
  }
}

/** Count of rows currently `processing` — used by the drain to know in-flight work. */
const inFlightStmt = raw.prepare(`SELECT COUNT(*) AS n FROM events WHERE status='processing'`);
export function inFlightCount(): number {
  return (inFlightStmt.get() as { n: number }).n;
}

// Re-export the drizzle handle for callers that want it (scheduler reads).
export { db, schema };
