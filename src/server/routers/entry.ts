import { z } from "zod";
import { and, eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { entries, entrySources } from "@/db/schema";

const entrySourceEnum = z.enum(entrySources);

/**
 * Entry (journal) router (§4.d/§4.f) — writes stamp `userId` + `updatedAt`;
 * `delete` is a soft-delete tombstone scoped to `ctx.userId`.
 */
export const entryRouter = router({
  create: protectedProcedure
    .input(
      z.object({
        chapterId: z.string(),
        content: z.string().min(1),
        date: z.string().default(() => new Date().toISOString()),
        source: entrySourceEnum.default("manual"),
        /** §4.d idempotent replay: a client-minted UUID; a retried create resolves to the same row. */
        clientRef: z.string().uuid().optional(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        if (input.clientRef) {
          const existing = tx
            .select({ id: entries.id })
            .from(entries)
            .where(and(eq(entries.userId, ctx.userId), eq(entries.clientRef, input.clientRef)))
            .get();
          if (existing) return { id: existing.id };
        }
        const id = randomUUID();
        tx.insert(entries)
          .values({
            id,
            userId: ctx.userId,
            chapterId: input.chapterId,
            content: input.content,
            date: input.date,
            source: input.source,
            clientRef: input.clientRef ?? null,
            updatedAt: now,
          })
          .run();
        return { id };
      });
    }),

  delete: protectedProcedure.input(z.string()).mutation(async ({ input, ctx }) => {
    const now = new Date().toISOString();
    db.update(entries)
      .set({ deletedAt: now, updatedAt: now })
      .where(and(eq(entries.id, input), eq(entries.userId, ctx.userId)))
      .run();
    return { ok: true };
  }),
});
