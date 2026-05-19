import { z } from "zod";
import { eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { decisions } from "@/db/schema";

export const decisionRouter = router({
  create: publicProcedure
    .input(
      z.object({
        chapterId: z.string(),
        title: z.string().min(1),
        rationale: z.string().optional().nullable(),
        optionsConsidered: z.string().optional().nullable(),
        decidedAt: z.string().default(() => new Date().toISOString()),
      })
    )
    .mutation(async ({ input }) => {
      const id = randomUUID();
      db.insert(decisions)
        .values({
          id,
          chapterId: input.chapterId,
          title: input.title,
          rationale: input.rationale ?? null,
          optionsConsidered: input.optionsConsidered ?? null,
          decidedAt: input.decidedAt,
        })
        .run();
      return { id };
    }),

  delete: publicProcedure.input(z.string()).mutation(async ({ input }) => {
    db.delete(decisions).where(eq(decisions.id, input)).run();
    return { ok: true };
  }),
});
