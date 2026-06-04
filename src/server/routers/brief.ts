import { z } from "zod";
import { and, eq, gt, gte, isNull, lte, or } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { briefs, devUnknownComponents, events, briefStatuses } from "@/db/schema";

const briefStatusEnum = z.enum(briefStatuses);

/**
 * Brief router (§4.d/§4.f) — read briefs by id, list briefs to surface on Today,
 * log unknown components. Every read filters `userId = ctx.userId AND deletedAt
 * IS NULL`; every mutation bumps `updatedAt`.
 */
export const briefRouter = router({
  // List briefs to show on Today: surfaced or draft, not expired, sorted soonest.
  forToday: protectedProcedure.query(({ ctx }) => {
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
          eq(briefs.userId, ctx.userId),
          isNull(briefs.deletedAt),
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
  recentByChapter: protectedProcedure.query(({ ctx }) => {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const rows = db
      .select({ chapterId: briefs.chapterId })
      .from(briefs)
      .where(and(eq(briefs.userId, ctx.userId), isNull(briefs.deletedAt), gte(briefs.createdAt, cutoff)))
      .all();
    const set = new Set<string>();
    for (const r of rows) if (r.chapterId) set.add(r.chapterId);
    return Array.from(set);
  }),

  byId: protectedProcedure.input(z.string()).query(({ input, ctx }) => {
    const row = db
      .select()
      .from(briefs)
      .where(and(eq(briefs.id, input), eq(briefs.userId, ctx.userId), isNull(briefs.deletedAt)))
      .get();
    return row ?? null;
  }),

  setStatus: protectedProcedure
    .input(z.object({ id: z.string(), status: briefStatusEnum }))
    .mutation(({ input, ctx }) => {
      db.update(briefs)
        .set({ status: input.status, updatedAt: new Date().toISOString() })
        .where(and(eq(briefs.id, input.id), eq(briefs.userId, ctx.userId), isNull(briefs.deletedAt)))
        .run();
      return { ok: true };
    }),

  /**
   * §4.a: the Brief Detail action strip's Start/Snooze. Maps an action to a
   * status transition, then emits a `brief_acted_on` event so the worker can
   * refine future reasoning. One round-trip for the screen.
   */
  act: protectedProcedure
    .input(
      z.object({
        id: z.string(),
        action: z.enum(["start", "snooze", "dismiss", "archive"]),
      })
    )
    .mutation(({ input, ctx }) => {
      const statusByAction: Record<string, (typeof briefStatuses)[number]> = {
        start: "acted_on",
        snooze: "draft",
        dismiss: "dismissed",
        archive: "archived",
      };
      const now = new Date().toISOString();
      const owned = and(
        eq(briefs.id, input.id),
        eq(briefs.userId, ctx.userId),
        isNull(briefs.deletedAt)
      );
      const brief = db.select({ id: briefs.id }).from(briefs).where(owned).get();
      if (!brief) return { ok: false };

      db.update(briefs).set({ status: statusByAction[input.action], updatedAt: now }).where(owned).run();
      db.insert(events)
        .values({
          id: randomUUID(),
          userId: ctx.userId,
          type: "brief_acted_on",
          payload: { briefId: input.id, action: input.action },
          updatedAt: now,
        })
        .run();
      return { ok: true };
    }),

  /**
   * Logs an unknown component_name from the renderer. Lets a dev see what
   * Atlas wanted that we haven't built yet, by querying dev_unknown_components.
   */
  logUnknownComponent: protectedProcedure
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
