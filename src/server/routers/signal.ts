import { z } from "zod";
import { count, desc, eq, gte } from "drizzle-orm";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { signals } from "@/db/schema";

/**
 * Signal router — surface aggregates ("Handled while you slept: 23 newsletters
 * filed, ...") and let UI peek into the raw inbox if needed.
 */
export const signalRouter = router({
  /**
   * Signals that arrived overnight (00:00 → "now"). Used by Today's
   * "Handled while you slept" line.
   */
  overnight: publicProcedure.query(() => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const cutoff = start.toISOString();
    const rows = db
      .select({ source: signals.source })
      .from(signals)
      .where(gte(signals.arrivedAt, cutoff))
      .all();
    // Bucket by source for the headline sentence.
    const buckets: Record<string, number> = {};
    for (const r of rows) buckets[r.source] = (buckets[r.source] ?? 0) + 1;
    return { total: rows.length, buckets };
  }),

  recent: publicProcedure
    .input(z.object({ limit: z.number().min(1).max(50).default(20) }).optional())
    .query(({ input }) => {
      const limit = input?.limit ?? 20;
      return db.select().from(signals).orderBy(desc(signals.arrivedAt)).limit(limit).all();
    }),
});
