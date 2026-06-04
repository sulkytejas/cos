import { z } from "zod";
import { and, eq, or, desc, isNull } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import {
  chapters,
  todos,
  decisions,
  entries,
  events,
  chapterLinks,
  chapterTypes,
  chapterStatuses,
  linkRelations,
} from "@/db/schema";

const chapterTypeEnum = z.enum(chapterTypes);
const chapterStatusEnum = z.enum(chapterStatuses);
const linkRelationEnum = z.enum(linkRelations);

/**
 * Chapter router (SERVER_ARCHITECTURE.md §4.d/§4.f).
 *
 * Every read filters `userId = ctx.userId AND deletedAt IS NULL`; every write
 * stamps `userId` and bumps `updatedAt`. `delete` is a SOFT delete with an
 * application-level cascade fan-out (§4.d): a hard FK cascade hard-deletes the
 * children, which a pull-by-cursor mirror could never observe — so we tombstone
 * the chapter AND its todos/decisions/entries/links in one transaction.
 */
export const chapterRouter = router({
  list: protectedProcedure.query(async ({ ctx }) => {
    const rows = db
      .select()
      .from(chapters)
      .where(and(eq(chapters.userId, ctx.userId), isNull(chapters.deletedAt)))
      .all();
    const allTodos = db
      .select()
      .from(todos)
      .where(and(eq(todos.userId, ctx.userId), isNull(todos.deletedAt)))
      .all();

    return rows
      .map((c) => {
        const t = allTodos.filter((x) => x.chapterId === c.id);
        const done = t.filter((x) => x.done).length;
        return {
          ...c,
          todoCount: t.length,
          todoDone: done,
          progress: t.length === 0 ? 0 : done / t.length,
        };
      })
      .sort((a, b) => {
        const order: Record<string, number> = {
          active: 0,
          upcoming: 1,
          paused: 2,
          done: 3,
        };
        return order[a.status] - order[b.status];
      });
  }),

  get: protectedProcedure.input(z.string()).query(async ({ input, ctx }) => {
    const chapter = db
      .select()
      .from(chapters)
      .where(
        and(eq(chapters.id, input), eq(chapters.userId, ctx.userId), isNull(chapters.deletedAt))
      )
      .get();
    if (!chapter) return null;

    const chTodos = db
      .select()
      .from(todos)
      .where(and(eq(todos.chapterId, input), eq(todos.userId, ctx.userId), isNull(todos.deletedAt)))
      .all()
      .sort((a, b) => {
        if (a.done !== b.done) return a.done ? 1 : -1;
        if (!a.dueDate && !b.dueDate) return 0;
        if (!a.dueDate) return 1;
        if (!b.dueDate) return -1;
        return a.dueDate.localeCompare(b.dueDate);
      });

    const chDecisions = db
      .select()
      .from(decisions)
      .where(
        and(
          eq(decisions.chapterId, input),
          eq(decisions.userId, ctx.userId),
          isNull(decisions.deletedAt)
        )
      )
      .all()
      .sort((a, b) => b.decidedAt.localeCompare(a.decidedAt));

    const chEntries = db
      .select()
      .from(entries)
      .where(
        and(eq(entries.chapterId, input), eq(entries.userId, ctx.userId), isNull(entries.deletedAt))
      )
      .all()
      .sort((a, b) => b.date.localeCompare(a.date));

    const linksRaw = db
      .select()
      .from(chapterLinks)
      .where(
        and(
          or(eq(chapterLinks.fromId, input), eq(chapterLinks.toId, input)),
          eq(chapterLinks.userId, ctx.userId),
          isNull(chapterLinks.deletedAt)
        )
      )
      .all();

    const otherIds = Array.from(
      new Set(linksRaw.map((l) => (l.fromId === input ? l.toId : l.fromId)))
    );

    const others = otherIds.length
      ? db
          .select()
          .from(chapters)
          .where(and(eq(chapters.userId, ctx.userId), isNull(chapters.deletedAt)))
          .all()
          .filter((c) => otherIds.includes(c.id))
      : [];

    const links = linksRaw.map((l) => {
      const otherId = l.fromId === input ? l.toId : l.fromId;
      const direction = l.fromId === input ? "outgoing" : "incoming";
      const other = others.find((c) => c.id === otherId);
      return {
        ...l,
        direction: direction as "outgoing" | "incoming",
        other,
      };
    });

    return {
      ...chapter,
      todos: chTodos,
      decisions: chDecisions,
      entries: chEntries,
      links,
    };
  }),

  create: protectedProcedure
    .input(
      z.object({
        title: z.string().min(1),
        type: chapterTypeEnum,
        status: chapterStatusEnum.default("active"),
        startDate: z.string().optional().nullable(),
        endDate: z.string().optional().nullable(),
        purpose: z.string().optional().nullable(),
        /**
         * §4.d idempotent replay: a client-minted UUID. An at-least-once outbox
         * replay of the same create resolves to the same row instead of a dup,
         * and the client reconciles its optimistic local row by matching this.
         */
        clientRef: z.string().uuid().optional(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        // §4.d: if this clientRef was already filed (a retry), return the
        // existing row's id and do NOT re-enqueue a second chapter_created.
        if (input.clientRef) {
          const existing = tx
            .select({ id: chapters.id })
            .from(chapters)
            .where(and(eq(chapters.userId, ctx.userId), eq(chapters.clientRef, input.clientRef)))
            .get();
          if (existing) return { id: existing.id };
        }

        const id = randomUUID();
        tx.insert(chapters)
          .values({
            id,
            userId: ctx.userId,
            title: input.title,
            type: input.type,
            status: input.status,
            startDate: input.startDate ?? null,
            endDate: input.endDate ?? null,
            purpose: input.purpose ?? null,
            clientRef: input.clientRef ?? null,
            updatedAt: now,
          })
          .run();
        // v0.2: notify the worker so Atlas can prepare an opening brief.
        tx.insert(events)
          .values({
            id: randomUUID(),
            userId: ctx.userId,
            type: "chapter_created",
            payload: { chapterId: id, title: input.title },
            updatedAt: now,
          })
          .run();
        return { id };
      });
    }),

  update: protectedProcedure
    .input(
      z.object({
        id: z.string(),
        title: z.string().min(1).optional(),
        type: chapterTypeEnum.optional(),
        status: chapterStatusEnum.optional(),
        startDate: z.string().optional().nullable(),
        endDate: z.string().optional().nullable(),
        purpose: z.string().optional().nullable(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { id, ...rest } = input;
      const patch: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined) patch[k] = v;
      }
      patch.updatedAt = new Date().toISOString();
      db.update(chapters)
        .set(patch)
        .where(and(eq(chapters.id, id), eq(chapters.userId, ctx.userId), isNull(chapters.deletedAt)))
        .run();
      return { ok: true };
    }),

  delete: protectedProcedure.input(z.string()).mutation(async ({ input, ctx }) => {
    // §4.d soft-delete + cascade fan-out: tombstone the chapter AND every child
    // in ONE transaction. A hard FK cascade would hard-delete children, which a
    // pull-by-cursor mirror can never observe (it keeps ghost rows forever).
    const now = new Date().toISOString();
    db.transaction((tx) => {
      const owned = and(eq(chapters.id, input), eq(chapters.userId, ctx.userId));
      // Only fan out if the chapter actually belongs to this user.
      const chapter = tx.select({ id: chapters.id }).from(chapters).where(owned).get();
      if (!chapter) return;

      tx.update(chapters)
        .set({ deletedAt: now, updatedAt: now })
        .where(owned)
        .run();
      tx.update(todos)
        .set({ deletedAt: now, updatedAt: now })
        .where(and(eq(todos.chapterId, input), eq(todos.userId, ctx.userId)))
        .run();
      tx.update(decisions)
        .set({ deletedAt: now, updatedAt: now })
        .where(and(eq(decisions.chapterId, input), eq(decisions.userId, ctx.userId)))
        .run();
      tx.update(entries)
        .set({ deletedAt: now, updatedAt: now })
        .where(and(eq(entries.chapterId, input), eq(entries.userId, ctx.userId)))
        .run();
      tx.update(chapterLinks)
        .set({ deletedAt: now, updatedAt: now })
        .where(
          and(
            or(eq(chapterLinks.fromId, input), eq(chapterLinks.toId, input)),
            eq(chapterLinks.userId, ctx.userId)
          )
        )
        .run();
    });
    return { ok: true };
  }),

  link: protectedProcedure
    .input(
      z.object({
        fromId: z.string(),
        toId: z.string(),
        relation: linkRelationEnum,
        note: z.string().optional().nullable(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const now = new Date().toISOString();
      // Upsert on the (fromId,toId,relation) synthetic key: re-linking a pair
      // that was previously tombstoned clears the tombstone and bumps updatedAt.
      db.insert(chapterLinks)
        .values({
          userId: ctx.userId,
          fromId: input.fromId,
          toId: input.toId,
          relation: input.relation,
          note: input.note ?? null,
          updatedAt: now,
          deletedAt: null,
        })
        .onConflictDoUpdate({
          target: [chapterLinks.fromId, chapterLinks.toId, chapterLinks.relation],
          set: { note: input.note ?? null, updatedAt: now, deletedAt: null },
        })
        .run();
      return { ok: true };
    }),

  unlink: protectedProcedure
    .input(
      z.object({
        fromId: z.string(),
        toId: z.string(),
        relation: linkRelationEnum,
      })
    )
    .mutation(async ({ input, ctx }) => {
      // Soft-delete so the mirror observes the tombstone (§4.d).
      const now = new Date().toISOString();
      db.update(chapterLinks)
        .set({ deletedAt: now, updatedAt: now })
        .where(
          and(
            eq(chapterLinks.fromId, input.fromId),
            eq(chapterLinks.toId, input.toId),
            eq(chapterLinks.relation, input.relation),
            eq(chapterLinks.userId, ctx.userId)
          )
        )
        .run();
      return { ok: true };
    }),

  recentlyActive: protectedProcedure.query(async ({ ctx }) => {
    return db
      .select()
      .from(chapters)
      .where(and(eq(chapters.userId, ctx.userId), isNull(chapters.deletedAt)))
      .orderBy(desc(chapters.updatedAt))
      .all();
  }),
});
