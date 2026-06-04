/**
 * Shared connector ingest with backpressure (SERVER_ARCHITECTURE.md §4.c) —
 * PER USER (§4.f Phase 5).
 *
 * Every connector (`gmail`/`calendar`/`drive`) feeds its freshly-fetched items
 * for ONE user through `ingestSignals`, which enforces the two backpressure rules
 * the spec requires:
 *
 *   1. **Cap per poll + pagination cursor.** At most `MAX_SIGNALS_PER_POLL` (20)
 *      new signals are ingested per `pollOnce` PER USER, and a persisted cursor
 *      (`connector_state.cursor`, keyed by `(userId, source)`) records the
 *      position reached in that user's upstream feed. A first-time Gmail backfill
 *      of hundreds of threads then drains over many polls instead of flooding the
 *      queue and exhausting the per-user daily budget before morning. The cursor
 *      survives a worker restart, so a backfill interrupted mid-drain resumes
 *      where it left off.
 *
 *   2. **Coalesce into ONE agent context.** All signals ingested in a single
 *      poll are written, then ONE `signal_received` event (owned by that user) is
 *      enqueued carrying `signalIds: string[]` — so the agent runs once over the
 *      batch rather than once per signal (`prepareSignalReceived` already reads
 *      `signalIds`). This is what stops a 20-item batch from fanning out into 20
 *      throttled Sonnet runs.
 *
 * The whole poll runs in ONE better-sqlite3 transaction: the signal inserts, the
 * coalesced event, and the cursor advance commit atomically, so a crash mid-poll
 * never advances the cursor past un-ingested items nor enqueues an event whose
 * signals were rolled back.
 */
import { randomUUID } from "node:crypto";
import { sqlite_, db, schema } from "../db";
import { and, eq } from "drizzle-orm";
import type { SignalSource } from "../../../src/db/schema";

/** Max new signals ingested per poll, per user (§4.c connector backpressure). */
export const MAX_SIGNALS_PER_POLL = Math.max(
  1,
  Number(process.env.CONNECTOR_MAX_SIGNALS_PER_POLL ?? 20),
);

/** One upstream item a connector hands us. */
export interface ConnectorItem {
  /** Stable upstream id — dedupe key for `(userId, source, externalId)`. */
  externalId: string;
  summary?: string | null;
  raw: Record<string, unknown>;
}

/** Result of one ingest pass — connectors log it. */
export interface IngestResult {
  /** New signals actually inserted this poll (≤ MAX_SIGNALS_PER_POLL). */
  inserted: number;
  /** The coalesced event id, or null when nothing new was ingested. */
  eventId: string | null;
  /** True if the cap was hit and items remain for the next poll. */
  more: boolean;
}

// ─────────────────────────── cursor helpers ───────────────────────────

/**
 * Read the persisted cursor for `(userId, source)` as an integer offset into the
 * feed. Defaults to 0 (start of feed) when no row exists yet. This integer cursor
 * is for the demo/fixture feeds (an index into a finite array). Real OAuth
 * connectors use their own opaque upstream tokens for pagination and pass an
 * already-sliced, never-before-seen batch with `useCursor: false`.
 */
function readCursor(userId: string, source: SignalSource): number {
  const row = db
    .select({ cursor: schema.connectorState.cursor })
    .from(schema.connectorState)
    .where(
      and(
        eq(schema.connectorState.userId, userId),
        eq(schema.connectorState.source, source),
      ),
    )
    .get();
  const n = row ? Number.parseInt(row.cursor, 10) : 0;
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

// ─────────────────────────── prepared statements ───────────────────────────
// Raw better-sqlite3 so the whole poll is one atomic transaction.

const raw = sqlite_;

// §4.d/§4.f: every ingested signal and the coalesced event are owned by the
// polling user, with `updated_at` stamped explicitly (rather than relying solely
// on the column DEFAULT).
const insertSignalStmt = raw.prepare(`
  INSERT INTO signals (id, user_id, source, external_id, summary, raw_data, processed, updated_at)
  VALUES (@id, @userId, @source, @externalId, @summary, @rawData, 0, @now)
`);

const insertEventStmt = raw.prepare(`
  INSERT INTO events (id, user_id, type, payload, status, attempts, updated_at)
  VALUES (@id, @userId, 'signal_received', @payload, 'pending', 0, @now)
`);

const upsertCursorStmt = raw.prepare(`
  INSERT INTO connector_state (user_id, source, cursor, updated_at)
  VALUES (@userId, @source, @cursor, @now)
  ON CONFLICT(user_id, source) DO UPDATE SET cursor = @cursor, updated_at = @now
`);

export interface IngestOptions {
  /** The owning user (per-user scoping, §4.f). */
  userId: string;
  /**
   * When true (default), `items` is the FULL feed in stable order and we slice
   * from the persisted integer cursor + cap (fixture/demo path). When false,
   * `items` is an already-paginated, never-before-seen batch (real OAuth path),
   * the integer cursor is ignored, and only the per-poll cap is applied.
   */
  useCursor?: boolean;
}

/**
 * Ingest a connector's freshly-fetched items for one user with backpressure.
 *
 * @param source the connector source (also part of the cursor / dedupe key).
 * @param items  the feed (FULL+ordered when `useCursor`, else an already-sliced batch).
 *
 * Items already present (matched on `(userId, source, externalId)`) are skipped
 * without consuming the per-poll cap — only genuinely new signals count toward 20.
 */
export function ingestSignals(
  source: SignalSource,
  items: ConnectorItem[],
  opts: IngestOptions,
): IngestResult {
  const { userId } = opts;
  const useCursor = opts.useCursor ?? true;

  const start = useCursor ? readCursor(userId, source) : 0;
  const slice = useCursor ? items.slice(start) : items;
  if (slice.length === 0) return { inserted: 0, eventId: null, more: false };

  const now = new Date().toISOString();
  const insertedIds: string[] = [];
  let consumed = 0; // how many feed positions we advance the cursor by
  let capped = false;

  const tx = raw.transaction(() => {
    for (const item of slice) {
      if (insertedIds.length >= MAX_SIGNALS_PER_POLL) {
        // Cap reached — stop here, leave the cursor at this position so the
        // remaining items drain on the next poll.
        capped = true;
        break;
      }
      consumed++;

      // Dedupe on (userId, source, externalId) — an already-ingested item
      // advances the cursor but does NOT consume the cap or re-enqueue.
      const existing = db
        .select({ id: schema.signals.id })
        .from(schema.signals)
        .where(
          and(
            eq(schema.signals.userId, userId),
            eq(schema.signals.source, source),
            eq(schema.signals.externalId, item.externalId),
          ),
        )
        .get();
      if (existing) continue;

      const id = randomUUID();
      insertSignalStmt.run({
        id,
        userId,
        source,
        externalId: item.externalId,
        summary: item.summary ?? null,
        rawData: JSON.stringify(item.raw),
        now,
      });
      insertedIds.push(id);
    }

    // Coalesce: ONE event for the whole batch, carrying every new signal id.
    let eventId: string | null = null;
    if (insertedIds.length > 0) {
      eventId = randomUUID();
      insertEventStmt.run({
        id: eventId,
        userId,
        payload: JSON.stringify({ signalIds: insertedIds }),
        now,
      });
    }

    // Advance the integer cursor past everything we examined this poll (fixture
    // path only — the real OAuth path persists its own opaque token elsewhere).
    if (useCursor) {
      upsertCursorStmt.run({ userId, source, cursor: String(start + consumed), now });
    }
    return eventId;
  });

  const eventId = tx();
  const more = useCursor ? capped || start + consumed < items.length : capped;
  return { inserted: insertedIds.length, eventId, more };
}
