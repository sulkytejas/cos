import { z } from "zod";
import { and, eq, or } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { todos, chapters, todoSources } from "@/db/schema";

const todoSourceEnum = z.enum(todoSources);

export const todoRouter = router({
  topAcrossActive: publicProcedure
    .input(z.object({ limit: z.number().min(1).max(20).default(5) }).optional())
    .query(async ({ input }) => {
      const limit = input?.limit ?? 5;
      const rows = db
        .select({
          id: todos.id,
          chapterId: todos.chapterId,
          text: todos.text,
          done: todos.done,
          dueDate: todos.dueDate,
          source: todos.source,
          createdAt: todos.createdAt,
          chapterTitle: chapters.title,
          chapterType: chapters.type,
          chapterStatus: chapters.status,
        })
        .from(todos)
        .innerJoin(chapters, eq(chapters.id, todos.chapterId))
        .where(
          and(
            eq(todos.done, false),
            or(eq(chapters.status, "active"), eq(chapters.status, "upcoming"))
          )
        )
        .all();

      const sorted = rows.sort((a, b) => {
        if (!a.dueDate && !b.dueDate) return 0;
        if (!a.dueDate) return 1;
        if (!b.dueDate) return -1;
        return a.dueDate.localeCompare(b.dueDate);
      });

      return sorted.slice(0, limit);
    }),

  create: publicProcedure
    .input(
      z.object({
        chapterId: z.string(),
        text: z.string().min(1),
        dueDate: z.string().optional().nullable(),
        source: todoSourceEnum.default("manual"),
      })
    )
    .mutation(async ({ input }) => {
      const id = randomUUID();
      db.insert(todos)
        .values({
          id,
          chapterId: input.chapterId,
          text: input.text,
          dueDate: input.dueDate ?? null,
          source: input.source,
        })
        .run();
      return { id };
    }),

  toggle: publicProcedure
    .input(z.object({ id: z.string(), done: z.boolean() }))
    .mutation(async ({ input }) => {
      db.update(todos)
        .set({
          done: input.done,
          doneAt: input.done ? new Date().toISOString() : null,
        })
        .where(eq(todos.id, input.id))
        .run();
      return { ok: true };
    }),

  update: publicProcedure
    .input(
      z.object({
        id: z.string(),
        text: z.string().min(1).optional(),
        dueDate: z.string().optional().nullable(),
      })
    )
    .mutation(async ({ input }) => {
      const { id, ...rest } = input;
      const patch: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined) patch[k] = v;
      }
      if (Object.keys(patch).length > 0) {
        db.update(todos).set(patch).where(eq(todos.id, id)).run();
      }
      return { ok: true };
    }),

  delete: publicProcedure.input(z.string()).mutation(async ({ input }) => {
    db.delete(todos).where(eq(todos.id, input)).run();
    return { ok: true };
  }),
});