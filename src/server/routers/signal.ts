import { z } from "zod";
import { and, desc, eq, gte, isNull, sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { signals, signalSources, events } from "@/db/schema";

const signalSourceEnum = z.enum(signalSources);

const IngestInput = z.object({
  /** Where this signal came from (gmail, calendar, drive, manual, voice). */
  source: signalSourceEnum,
  /**
   * Stable id from the source system — for iOS EventKit this is
   * `EKEvent.eventIdentifier`. REQUIRED for an upsert: the unique index is
   * `(userId, source, externalId)`, so re-pushing the same calendar event on
   * every foreground updates the existing row instead of duplicating it (§4.e).
   */
  externalId: z.string().trim().min(1).max(512),
  /** The raw payload (calendar event JSON, message stub, …). Bounded so a push
   *  can't balloon the queue/budget. */
  rawData: z.unknown().refine((v) => JSON.stringify(v ?? null).length <= 8_000, {
    message: "rawData too large (max 8k chars)",
  }),
  /** Short human-readable label shown in the review queue. */
  summary: z.string().max(500).optional(),
  /** When the signal occurred at the source (defaults to now if omitted). */
  arrivedAt: z.string().datetime().optional(),
});

/**
 * Signal router (§4.d/§4.f) — surface aggregates ("Handled while you slept: 23
 * newsletters filed, ...") and let UI peek into the raw inbox. All reads are
 * scoped to `ctx.userId` with `deletedAt IS NULL`.
 */
export const signalRouter = router({
  /**
   * Signals that arrived overnight (00:00 → "now"). Used by Today's
   * "Handled while you slept" line.
   */
  overnight: protectedProcedure.query(({ ctx }) => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const cutoff = start.toISOString();
    const rows = db
      .select({ source: signals.source })
      .from(signals)
      .where(
        and(eq(signals.userId, ctx.userId), isNull(signals.deletedAt), gte(signals.arrivedAt, cutoff))
      )
      .all();
    // Bucket by source for the headline sentence.
    const buckets: Record<string, number> = {};
    for (const r of rows) buckets[r.source] = (buckets[r.source] ?? 0) + 1;
    return { total: rows.length, buckets };
  }),

  recent: protectedProcedure
    .input(z.object({ limit: z.number().min(1).max(50).default(20) }).optional())
    .query(({ input, ctx }) => {
      const limit = input?.limit ?? 20;
      return db
        .select()
        .from(signals)
        .where(and(eq(signals.userId, ctx.userId), isNull(signals.deletedAt)))
        .orderBy(desc(signals.arrivedAt))
        .limit(limit)
        .all();
    }),

  /**
   * §4.e: the iOS EventKit push source. `EventKitCalendarSource.swift` is
   * device-only, so iOS pushes the device calendar here on every foreground via
   * `repo.pushCalendarSignals()`. UPSERTS on `(userId, source, externalId)` so a
   * per-foreground re-push of the same calendar event updates the existing row
   * (rawData/summary/arrivedAt) instead of creating a duplicate signal.
   *
   * On a genuinely NEW signal (a row that did not exist before), we enqueue a
   * `signal_received` event so the worker can decide whether it warrants a brief
   * or proposals. We must NOT re-enqueue on an idempotent re-push of an unchanged
   * event — so we detect insert-vs-update via a transition guard: clear
   * `deletedAt` and bump `updatedAt` always, but only flip `processed` back to
   * false (and enqueue) when the row is newly created. `xmax`-style detection
   * isn't available in SQLite, so we check existence inside the same write txn.
   */
  ingest: protectedProcedure.input(IngestInput).mutation(({ input, ctx }) => {
    const now = new Date().toISOString();
    const arrivedAt = input.arrivedAt ?? now;

    return db.transaction((tx) => {
      // Was there already a (live or tombstoned) row for this external event?
      const existing = tx
        .select({ id: signals.id, processed: signals.processed })
        .from(signals)
        .where(
          and(
            eq(signals.userId, ctx.userId),
            eq(signals.source, input.source),
            eq(signals.externalId, input.externalId),
          ),
        )
        .get();

      const id = existing?.id ?? randomUUID();

      tx.insert(signals)
        .values({
          id,
          userId: ctx.userId,
          source: input.source,
          externalId: input.externalId,
          rawData: input.rawData,
          summary: input.summary ?? null,
          processed: false,
          arrivedAt,
          updatedAt: now,
          deletedAt: null,
        })
        // Restate the partial index's predicate so SQLite matches the
        // `(user_id, source, external_id)` unique index. On conflict, refresh the
        // mutable fields and un-tombstone — but DON'T reset `processed` here; an
        // already-processed event that re-pushes unchanged must not re-brief.
        .onConflictDoUpdate({
          target: [signals.userId, signals.source, signals.externalId],
          targetWhere: sql`${signals.externalId} IS NOT NULL`,
          set: {
            rawData: input.rawData,
            summary: input.summary ?? null,
            arrivedAt,
            updatedAt: now,
            deletedAt: null,
          },
        })
        .run();

      // Only a brand-new signal gets handed to the worker. An idempotent re-push
      // (row already existed) does not re-enqueue — that's the whole point of the
      // upsert: a per-foreground push doesn't flood the queue or the budget.
      const isNew = !existing;
      if (isNew) {
        tx.insert(events)
          .values({
            id: randomUUID(),
            userId: ctx.userId,
            type: "signal_received",
            payload: { signalId: id },
            updatedAt: now,
          })
          .run();
      }

      return { id, isNew };
    });
  }),
});
