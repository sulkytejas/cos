import { z } from "zod";
import { and, eq, or, desc } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import {
  chapters,
  todos,
  decisions,
  entries,
  chapterLinks,
  chapterTypes,
  chapterStatuses,
  linkRelations,
} from "@/db/schema";

const chapterTypeEnum = z.enum(chapterTypes);
const chapterStatusEnum = z.enum(chapterStatuses);
const linkRelationEnum = z.enum(linkRelations);

export const chapterRouter = router({
  list: publicProcedure.query(async () => {
    const rows = db.select().from(chapters).all();
    const allTodos = db.select().from(todos).all();

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

  get: publicProcedure.input(z.string()).query(async ({ input }) => {
    const chapter = db.select().from(chapters).where(eq(chapters.id, input)).get();
    if (!chapter) return null;

    const chTodos = db
      .select()
      .from(todos)
      .where(eq(todos.chapterId, input))
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
      .where(eq(decisions.chapterId, input))
      .all()
      .sort((a, b) => b.decidedAt.localeCompare(a.decidedAt));

    const chEntries = db
      .select()
      .from(entries)
      .where(eq(entries.chapterId, input))
      .all()
      .sort((a, b) => b.date.localeCompare(a.date));

    const linksRaw = db
      .select()
      .from(chapterLinks)
      .where(or(eq(chapterLinks.fromId, input), eq(chapterLinks.toId, input)))
      .all();

    const otherIds = Array.from(
      new Set(linksRaw.map((l) => (l.fromId === input ? l.toId : l.fromId)))
    );

    const others = otherIds.length
      ? db.select().from(chapters).all().filter((c) => otherIds.includes(c.id))
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

  create: publicProcedure
    .input(
      z.object({
        title: z.string().min(1),
        type: chapterTypeEnum,
        status: chapterStatusEnum.default("active"),
        startDate: z.string().optional().nullable(),
        endDate: z.string().optional().nullable(),
        purpose: z.string().optional().nullable(),
      })
    )
    .mutation(async ({ input }) => {
      const id = randomUUID();
      db.insert(chapters)
        .values({
          id,
          title: input.title,
          type: input.type,
          status: input.status,
          startDate: input.startDate ?? null,
          endDate: input.endDate ?? null,
          purpose: input.purpose ?? null,
        })
        .run();
      return { id };
    }),

  update: publicProcedure
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
    .mutation(async ({ input }) => {
      const { id, ...rest } = input;
      const patch: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined) patch[k] = v;
      }
      patch.updatedAt = new Date().toISOString();
      if (Object.keys(patch).length > 0) {
        db.update(chapters).set(patch).where(eq(chapters.id, id)).run();
      }
      return { ok: true };
    }),

  delete: publicProcedure.input(z.string()).mutation(async ({ input }) => {
    db.delete(chapters).where(eq(chapters.id, input)).run();
    return { ok: true };
  }),

  link: publicProcedure
    .input(
      z.object({
        fromId: z.string(),
        toId: z.string(),
        relation: linkRelationEnum,
        note: z.string().optional().nullable(),
      })
    )
    .mutation(async ({ input }) => {
      db.insert(chapterLinks)
        .values({
          fromId: input.fromId,
          toId: input.toId,
          relation: input.relation,
          note: input.note ?? null,
        })
        .run();
      return { ok: true };
    }),

  unlink: publicProcedure
    .input(
      z.object({
        fromId: z.string(),
        toId: z.string(),
        relation: linkRelationEnum,
      })
    )
    .mutation(async ({ input }) => {
      db.delete(chapterLinks)
        .where(
          and(
            eq(chapterLinks.fromId, input.fromId),
            eq(chapterLinks.toId, input.toId),
            eq(chapterLinks.relation, input.relation)
          )
        )
        .run();
      return { ok: true };
    }),

  recentlyActive: publicProcedure.query(async () => {
    return db
      .select()
      .from(chapters)
      .orderBy(desc(chapters.updatedAt))
      .all();
  }),
});
