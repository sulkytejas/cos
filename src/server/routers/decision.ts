import { z } from "zod";
import { and, eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { decisions } from "@/db/schema";

/**
 * Decision router (§4.d/§4.f) — writes stamp `userId` + `updatedAt`; `delete`
 * is a soft-delete tombstone scoped to `ctx.userId`.
 */
export const decisionRouter = router({
  create: protectedProcedure
    .input(
      z.object({
        chapterId: z.string(),
        title: z.string().min(1),
        rationale: z.string().optional().nullable(),
        optionsConsidered: z.string().optional().nullable(),
        decidedAt: z.string().default(() => new Date().toISOString()),
        /** §4.d idempotent replay: a client-minted UUID; a retried create resolves to the same row. */
        clientRef: z.string().uuid().optional(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        if (input.clientRef) {
          const existing = tx
            .select({ id: decisions.id })
            .from(decisions)
            .where(and(eq(decisions.userId, ctx.userId), eq(decisions.clientRef, input.clientRef)))
            .get();
          if (existing) return { id: existing.id };
        }
        const id = randomUUID();
        tx.insert(decisions)
          .values({
            id,
            userId: ctx.userId,
            chapterId: input.chapterId,
            title: input.title,
            rationale: input.rationale ?? null,
            optionsConsidered: input.optionsConsidered ?? null,
            decidedAt: input.decidedAt,
            clientRef: input.clientRef ?? null,
            updatedAt: now,
          })
          .run();
        return { id };
      });
    }),

  delete: protectedProcedure.input(z.string()).mutation(async ({ input, ctx }) => {
    const now = new Date().toISOString();
    db.update(decisions)
      .set({ deletedAt: now, updatedAt: now })
      .where(and(eq(decisions.id, input), eq(decisions.userId, ctx.userId)))
      .run();
    return { ok: true };
  }),
});
