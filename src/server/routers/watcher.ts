import { desc, eq } from "drizzle-orm";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { watchers } from "@/db/schema";

/**
 * Watcher router — read active watchers for Today's "Atlas is watching" strip.
 */
export const watcherRouter = router({
  active: publicProcedure.query(() => {
    return db
      .select()
      .from(watchers)
      .where(eq(watchers.status, "active"))
      .orderBy(desc(watchers.createdAt))
      .all();
  }),
});
