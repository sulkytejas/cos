import { z } from "zod";
import { and, eq, isNull, or } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { todos, chapters, todoSources } from "@/db/schema";

const todoSourceEnum = z.enum(todoSources);

/**
 * Todo router (§4.d/§4.f) — every read filters `userId = ctx.userId AND
 * deletedAt IS NULL`; every write stamps `userId` and bumps `updatedAt`;
 * `delete` is a soft-delete tombstone.
 */
export const todoRouter = router({
  topAcrossActive: protectedProcedure
    .input(z.object({ limit: z.number().min(1).max(20).default(5) }).optional())
    .query(async ({ input, ctx }) => {
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
            eq(todos.userId, ctx.userId),
            isNull(todos.deletedAt),
            isNull(chapters.deletedAt),
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

  create: protectedProcedure
    .input(
      z.object({
        chapterId: z.string(),
        text: z.string().min(1),
        dueDate: z.string().optional().nullable(),
        source: todoSourceEnum.default("manual"),
        /** §4.d idempotent replay: a client-minted UUID; a retried create resolves to the same row. */
        clientRef: z.string().uuid().optional(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        if (input.clientRef) {
          const existing = tx
            .select({ id: todos.id })
            .from(todos)
            .where(and(eq(todos.userId, ctx.userId), eq(todos.clientRef, input.clientRef)))
            .get();
          if (existing) return { id: existing.id };
        }
        const id = randomUUID();
        tx.insert(todos)
          .values({
            id,
            userId: ctx.userId,
            chapterId: input.chapterId,
            text: input.text,
            dueDate: input.dueDate ?? null,
            source: input.source,
            clientRef: input.clientRef ?? null,
            updatedAt: now,
          })
          .run();
        return { id };
      });
    }),

  toggle: protectedProcedure
    .input(z.object({ id: z.string(), done: z.boolean() }))
    .mutation(async ({ input, ctx }) => {
      const now = new Date().toISOString();
      db.update(todos)
        .set({
          done: input.done,
          doneAt: input.done ? now : null,
          updatedAt: now,
        })
        .where(and(eq(todos.id, input.id), eq(todos.userId, ctx.userId), isNull(todos.deletedAt)))
        .run();
      return { ok: true };
    }),

  update: protectedProcedure
    .input(
      z.object({
        id: z.string(),
        text: z.string().min(1).optional(),
        dueDate: z.string().optional().nullable(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { id, ...rest } = input;
      const patch: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined) patch[k] = v;
      }
      patch.updatedAt = new Date().toISOString();
      db.update(todos)
        .set(patch)
        .where(and(eq(todos.id, id), eq(todos.userId, ctx.userId), isNull(todos.deletedAt)))
        .run();
      return { ok: true };
    }),

  delete: protectedProcedure.input(z.string()).mutation(async ({ input, ctx }) => {
    const now = new Date().toISOString();
    db.update(todos)
      .set({ deletedAt: now, updatedAt: now })
      .where(and(eq(todos.id, input), eq(todos.userId, ctx.userId)))
      .run();
    return { ok: true };
  }),
});
