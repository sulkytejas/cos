import { z } from "zod";
import { eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { entries, entrySources } from "@/db/schema";

const entrySourceEnum = z.enum(entrySources);

export const entryRouter = router({
  create: publicProcedure
    .input(
      z.object({
        chapterId: z.string(),
        content: z.string().min(1),
        date: z.string().default(() => new Date().toISOString()),
        source: entrySourceEnum.default("manual"),
      })
    )
    .mutation(async ({ input }) => {
      const id = randomUUID();
      db.insert(entries)
        .values({
          id,
          chapterId: input.chapterId,
          content: input.content,
          date: input.date,
          source: input.source,
        })
        .run();
      return { id };
    }),

  delete: publicProcedure.input(z.string()).mutation(async ({ input }) => {
    db.delete(entries).where(eq(entries.id, input)).run();
    return { ok: true };
  }),
});
