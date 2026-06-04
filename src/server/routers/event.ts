import { z } from "zod";
import { and, eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { events, eventTypes } from "@/db/schema";

const eventTypeEnum = z.enum(eventTypes);

/**
 * Events router — the bridge between the web app and the worker (§4.a).
 * The web app writes events here on user actions; the worker polls.
 *
 * §4.d/§4.f: every event is stamped with `ctx.userId` so the worker can scope
 * the intent to its emitter, and `status` reads are scoped to the caller's user
 * — a device may only poll the status of events it emitted.
 */
export const eventRouter = router({
  emit: protectedProcedure
    .input(
      z.object({
        type: eventTypeEnum,
        // §4.a hardening: bound the payload size before it lands in the queue —
        // the worker feeds it into an Anthropic-touching agent run. ~16k chars
        // is generous for a capture/signal envelope.
        payload: z.unknown().refine(
          (v) => JSON.stringify(v ?? null).length <= 16_000,
          { message: "payload too large (max 16k chars)" }
        ),
      })
    )
    .mutation(({ input, ctx }) => {
      const id = randomUUID();
      db.insert(events)
        .values({
          id,
          userId: ctx.userId,
          type: input.type,
          payload: input.payload,
          updatedAt: new Date().toISOString(),
        })
        .run();
      return { id };
    }),

  /**
   * The submit→poll→read status read (§4.a). Used by:
   *  - Capture: show "Atlas is thinking…" until the worker marks the event done,
   *    then render exactly the proposals this capture produced via
   *    `result.resultProposalIds` (NOT a `createdAt >= sendStart` window — a
   *    background scan can interleave proposals into that window).
   *  - Ask: the grounded one-shot enqueued by `ai.ask`; on `done`, `result`
   *    carries `{ answer, resultProposalIds }`.
   *
   * `result` is JSON written by the worker's commit phase in the SAME txn as
   * `status='done'`, so it is always present once `status === 'done'` for jobs
   * that produce one. Scoped to the caller's user — a device may only poll the
   * status of events it emitted.
   */
  status: protectedProcedure.input(z.string()).query(({ input, ctx }) => {
    const row = db
      .select({
        status: events.status,
        error: events.error,
        processedAt: events.processedAt,
        result: events.result,
      })
      .from(events)
      .where(and(eq(events.id, input), eq(events.userId, ctx.userId)))
      .get();
    return row ?? null;
  }),
});
