import { and, desc, eq, isNull } from "drizzle-orm";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { watchers } from "@/db/schema";

/**
 * Watcher router (§4.d/§4.f) — read active watchers for Today's "Atlas is
 * watching" strip, scoped to `ctx.userId` with `deletedAt IS NULL`.
 */
export const watcherRouter = router({
  active: protectedProcedure.query(({ ctx }) => {
    return db
      .select()
      .from(watchers)
      .where(
        and(eq(watchers.userId, ctx.userId), isNull(watchers.deletedAt), eq(watchers.status, "active"))
      )
      .orderBy(desc(watchers.createdAt))
      .all();
  }),
});
