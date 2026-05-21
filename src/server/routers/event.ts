import { z } from "zod";
import { and, eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { events, eventTypes } from "@/db/schema";

const eventTypeEnum = z.enum(eventTypes);

/**
 * Events router — the bridge between the web app and the worker.
 * The web app writes events here on user actions; the worker polls.
 */
export const eventRouter = router({
  emit: publicProcedure
    .input(
      z.object({
        type: eventTypeEnum,
        payload: z.unknown(),
      })
    )
    .mutation(({ input }) => {
      const id = randomUUID();
      db.insert(events).values({ id, type: input.type, payload: input.payload }).run();
      return { id };
    }),

  /**
   * Used by the Capture sheet to show "Atlas is thinking…" until the worker
   * has marked the event done.
   */
  status: publicProcedure.input(z.string()).query(({ input }) => {
    const row = db
      .select({ status: events.status, error: events.error, processedAt: events.processedAt })
      .from(events)
      .where(eq(events.id, input))
      .get();
    return row ?? null;
  }),
});
