import { z } from "zod";
import { and, desc, eq, gt, gte, isNull, lte, or } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { briefs, chapters, devUnknownComponents, briefStatuses } from "@/db/schema";

const briefStatusEnum = z.enum(briefStatuses);

/**
 * Brief router — read briefs by id, list briefs to surface on Today, log
 * unknown components from the renderer for dev visibility.
 */
export const briefRouter = router({
  // List briefs to show on Today: surfaced or draft, not expired, sorted soonest.
  forToday: publicProcedure.query(() => {
    const now = new Date().toISOString();
    const rows = db
      .select({
        id: briefs.id,
        chapterId: briefs.chapterId,
        title: briefs.title,
        situationDescription: briefs.situationDescription,
        chapterTitle: briefs.chapterTitle,
        relevance: briefs.relevance,
        when: briefs.when,
        drafted: briefs.drafted,
        preview: briefs.preview,
        status: briefs.status,
        surfaceAt: briefs.surfaceAt,
        createdAt: briefs.createdAt,
      })
      .from(briefs)
      .where(
        and(
          or(eq(briefs.status, "surfaced"), eq(briefs.status, "draft")),
          lte(briefs.surfaceAt, now),
          or(isNull(briefs.expiresAt), gt(briefs.expiresAt, now))
        )
      )
      .orderBy(briefs.surfaceAt)
      .all();
    return rows;
  }),

  // Briefs created by Atlas in the last 24h (used by Constellation to pulse chapters)
  recentByChapter: publicProcedure.query(() => {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const rows = db
      .select({ chapterId: briefs.chapterId })
      .from(briefs)
      .where(gte(briefs.createdAt, cutoff))
      .all();
    const set = new Set<string>();
    for (const r of rows) if (r.chapterId) set.add(r.chapterId);
    return Array.from(set);
  }),

  byId: publicProcedure.input(z.string()).query(({ input }) => {
    const row = db.select().from(briefs).where(eq(briefs.id, input)).get();
    return row ?? null;
  }),

  setStatus: publicProcedure
    .input(z.object({ id: z.string(), status: briefStatusEnum }))
    .mutation(({ input }) => {
      db.update(briefs).set({ status: input.status }).where(eq(briefs.id, input.id)).run();
      return { ok: true };
    }),

  /**
   * Logs an unknown component_name from the renderer. Lets a dev see what
   * Atlas wanted that we haven't built yet, by querying dev_unknown_components.
   */
  logUnknownComponent: publicProcedure
    .input(
      z.object({
        briefId: z.string(),
        componentName: z.string(),
        rawProps: z.unknown().optional(),
      })
    )
    .mutation(({ input }) => {
      db.insert(devUnknownComponents)
        .values({
          id: randomUUID(),
          briefId: input.briefId,
          componentName: input.componentName,
          rawProps: input.rawProps ?? null,
        })
        .run();
      return { ok: true };
    }),
});
