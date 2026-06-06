import { z } from "zod";
import { and, eq, or, gt, asc, sql, type SQL } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import {
  chapters,
  todos,
  decisions,
  entries,
  chapterLinks,
  briefs,
  watchers,
  signals,
  proposals,
  turns,
} from "@/db/schema";

/**
 * Delta-sync router (SERVER_ARCHITECTURE.md §4.d).
 *
 * The server SQLite is the source of truth; iOS SwiftData is a read-mirror.
 * `pull` streams every change (inserts, edits, and tombstones) since the
 * client's last cursor; `bootstrap` runs the one-way `local→server` cut-over,
 * uploading the device's local-only rows, assigning them server ids, and
 * returning the id mapping so the client can rewrite its local ids.
 *
 * ── Cursor (§4.d) ───────────────────────────────────────────────────────────
 * Per the spec the cursor is `(updatedAt, id)` and rows are ordered by
 * `(updatedAt, id)`: `WHERE updatedAt > iso OR (updatedAt = iso AND id > lastId)`.
 * This is monotonic ONLY because the 0008 migration normalized every timestamp
 * to ISO-8601-UTC (lexical == chronological) and switched the defaults to ISO —
 * otherwise a `' ' < 'T'` mix would make a string-compare cursor skip rows.
 * Tombstones (soft-deleted rows) ride the SAME cursor — they keep being updated
 * (`updatedAt` bumped on delete) so the mirror observes the deletion as a normal
 * delta and drops the row, instead of keeping a ghost forever.
 *
 * ── ID parity (§4.d) ────────────────────────────────────────────────────────
 * Both sides pin a canonical lowercase text-UUID (`canonicalId`), so an
 * upsert-by-id can't silently dup an uppercased-vs-lowercased pair. `chapter_links`
 * has no row id, so its sync key is the synthetic `from|to|relation` triple
 * (`linkSyncKey`); the cursor for that table orders by `(updatedAt, syncKey)`.
 */

// ─────────────────────────── id parity helpers ───────────────────────────

/**
 * Canonical id form shared by both sides (§4.d): a lowercase text-UUID. iOS
 * `@Model` ids serialize as uppercase UUID strings; the server stores lowercase.
 * Lowercasing on every boundary makes upsert-by-id collision-free.
 */
export function canonicalId(id: string): string {
  return id.trim().toLowerCase();
}

/** Synthetic sync key for `chapter_links` (no row id): `from|to|relation`, canonical. */
export function linkSyncKey(fromId: string, toId: string, relation: string): string {
  return `${canonicalId(fromId)}|${canonicalId(toId)}|${relation}`;
}

// ─────────────────────────── table registry ───────────────────────────

/**
 * The synced tables, in a stable order. Everything user-owned that the mirror
 * renders. (Auth/ledger/connector-state/events/dev tables are server-internal
 * and never mirrored.) `chapter_links` is handled separately because it keys on
 * the synthetic triple rather than an `id` column.
 */
const ID_TABLES = {
  chapters,
  todos,
  decisions,
  entries,
  briefs,
  watchers,
  signals,
  proposals,
  turns,
} as const;

type IdTableName = keyof typeof ID_TABLES;
const ID_TABLE_NAMES = Object.keys(ID_TABLES) as IdTableName[];

/** Per-table cursor: the `(updatedAt, id)` of the last row the client consumed. */
const CursorSchema = z
  .object({ updatedAt: z.string(), id: z.string() })
  .nullable();

const MAX_PAGE = 500;

// ─────────────────────────── pull ───────────────────────────

/**
 * One table's slice of a pull. The client tracks one cursor per table and asks
 * for the tables it wants (or all). Each slice returns the next page of rows
 * (live AND tombstoned — the client applies a tombstone by deleting its mirror
 * row), the cursor to resume from, and whether more remain.
 */
function pullIdTable(
  userId: string,
  name: IdTableName,
  cursor: { updatedAt: string; id: string } | null,
  limit: number
) {
  const table = ID_TABLES[name];
  // (updatedAt > c.updatedAt) OR (updatedAt = c.updatedAt AND id > c.id)
  const after: SQL | undefined = cursor
    ? or(
        gt(table.updatedAt, cursor.updatedAt),
        and(eq(table.updatedAt, cursor.updatedAt), gt(table.id, cursor.id))
      )
    : undefined;

  const rows = db
    .select()
    .from(table)
    .where(and(eq(table.userId, userId), after))
    // Ordered by (updatedAt, id) so the cursor is total and gap-free across pages.
    .orderBy(asc(table.updatedAt), asc(table.id))
    .limit(limit + 1)
    .all() as Array<Record<string, unknown> & { id: string; updatedAt: string; deletedAt: string | null }>;

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;

  const last = page[page.length - 1];
  const nextCursor = last ? { updatedAt: last.updatedAt, id: last.id } : cursor;

  // Tombstones are surfaced separately so the client can drop those mirror rows
  // without parsing the (still-present-but-soft-deleted) row bodies.
  const tombstones = page.filter((r) => r.deletedAt != null).map((r) => r.id);
  const upserts = page.filter((r) => r.deletedAt == null);

  return { rows: upserts, tombstones, nextCursor, hasMore };
}

/** `chapter_links` pull — keyed on the synthetic `from|to|relation` triple. */
function pullLinks(
  userId: string,
  cursor: { updatedAt: string; id: string } | null,
  limit: number
) {
  // For links the cursor's `id` is the synthetic syncKey. We can't compute the
  // syncKey in SQL portably for the tie-break, so we over-select by updatedAt
  // and resolve the within-same-timestamp tie-break in JS. A page is bounded by
  // `limit`, so the worst case is one extra same-millisecond cluster — fine.
  const after: SQL | undefined = cursor
    ? sql`${chapterLinks.updatedAt} >= ${cursor.updatedAt}`
    : undefined;

  const all = db
    .select()
    .from(chapterLinks)
    .where(and(eq(chapterLinks.userId, userId), after))
    .orderBy(asc(chapterLinks.updatedAt))
    .all();

  // Decorate with the synthetic key and apply the full (updatedAt, syncKey)
  // cursor in JS so the tie-break inside one timestamp is total.
  const decorated = all
    .map((r) => ({ ...r, syncKey: linkSyncKey(r.fromId, r.toId, r.relation) }))
    .filter((r) => {
      if (!cursor) return true;
      if (r.updatedAt > cursor.updatedAt) return true;
      if (r.updatedAt === cursor.updatedAt) return r.syncKey > cursor.id;
      return false;
    })
    .sort((a, b) =>
      a.updatedAt === b.updatedAt
        ? a.syncKey.localeCompare(b.syncKey)
        : a.updatedAt.localeCompare(b.updatedAt)
    );

  const hasMore = decorated.length > limit;
  const page = hasMore ? decorated.slice(0, limit) : decorated;
  const last = page[page.length - 1];
  const nextCursor = last ? { updatedAt: last.updatedAt, id: last.syncKey } : cursor;

  const tombstones = page.filter((r) => r.deletedAt != null).map((r) => r.syncKey);
  const upserts = page.filter((r) => r.deletedAt == null);

  return { rows: upserts, tombstones, nextCursor, hasMore };
}

export const syncRouter = router({
  /**
   * Pull all deltas since the client's per-table cursors. The client passes the
   * cursor it last received for each table (or null on first sync) and a page
   * limit; the server returns, per table, the next page of upserts + tombstones,
   * the resume cursor, and `hasMore`. The client loops `pull` until every
   * table's `hasMore` is false — that's how a 500-row single-tick burst drains
   * across pages with no skips/repeats (the cursor is total and monotonic).
   */
  pull: protectedProcedure
    .input(
      z
        .object({
          cursors: z.record(z.string(), CursorSchema).optional(),
          limit: z.number().int().min(1).max(MAX_PAGE).default(MAX_PAGE),
          /** Restrict to a subset of tables; omit for all. */
          tables: z.array(z.string()).optional(),
        })
        .optional()
    )
    .query(({ input, ctx }) => {
      const limit = input?.limit ?? MAX_PAGE;
      const cursors = input?.cursors ?? {};
      const wanted = input?.tables;

      const result: Record<
        string,
        {
          rows: unknown[];
          tombstones: string[];
          nextCursor: { updatedAt: string; id: string } | null;
          hasMore: boolean;
        }
      > = {};

      let anyMore = false;

      for (const name of ID_TABLE_NAMES) {
        if (wanted && !wanted.includes(name)) continue;
        const slice = pullIdTable(ctx.userId, name, cursors[name] ?? null, limit);
        result[name] = slice;
        anyMore = anyMore || slice.hasMore;
      }

      if (!wanted || wanted.includes("chapter_links")) {
        const links = pullLinks(ctx.userId, cursors["chapter_links"] ?? null, limit);
        result["chapter_links"] = links;
        anyMore = anyMore || links.hasMore;
      }

      // `serverTime` lets the client sanity-check clock skew; conflict policy is
      // server-stamped-on-receipt, so the client never compares against this.
      return { tables: result, hasMore: anyMore, serverTime: new Date().toISOString() };
    }),

  /**
   * One-way `local→server` bootstrap (§4.d). When the device flips its
   * `DataSource` flag from `.local` to `.server`, it uploads the rows it created
   * locally (before sync existed) so they aren't lost. Each upload carries the
   * row's local id as `clientRef`; the server assigns a fresh canonical server
   * id (or reuses the existing row if this `clientRef` was already uploaded —
   * idempotent re-run) and returns the `localId → serverId` mapping per table so
   * the client can rewrite its local ids and FKs.
   *
   * Chapters must be uploaded (and mapped) before their children so child FKs
   * can be rewritten to the new chapter ids client-side; the server resolves
   * each child's `chapterRef` (the parent's local id) against the chapter
   * mapping produced in THIS same call, inside one transaction.
   */
  bootstrap: protectedProcedure
    .input(
      z.object({
        chapters: z
          .array(
            z.object({
              clientRef: z.string().min(1),
              title: z.string().min(1),
              type: z.string(),
              status: z.string().default("active"),
              startDate: z.string().nullable().optional(),
              endDate: z.string().nullable().optional(),
              purpose: z.string().nullable().optional(),
              createdAt: z.string().optional(),
              updatedAt: z.string().optional(),
            })
          )
          .default([]),
        todos: z
          .array(
            z.object({
              clientRef: z.string().min(1),
              /** The parent chapter's LOCAL id (clientRef); resolved to the new server id. */
              chapterRef: z.string().min(1),
              text: z.string().min(1),
              done: z.boolean().default(false),
              dueDate: z.string().nullable().optional(),
              source: z.string().default("manual"),
              createdAt: z.string().optional(),
              updatedAt: z.string().optional(),
            })
          )
          .default([]),
        decisions: z
          .array(
            z.object({
              clientRef: z.string().min(1),
              chapterRef: z.string().min(1),
              title: z.string().min(1),
              rationale: z.string().nullable().optional(),
              optionsConsidered: z.string().nullable().optional(),
              decidedAt: z.string(),
              source: z.string().default("manual"),
              createdAt: z.string().optional(),
              updatedAt: z.string().optional(),
            })
          )
          .default([]),
        entries: z
          .array(
            z.object({
              clientRef: z.string().min(1),
              chapterRef: z.string().min(1),
              date: z.string(),
              content: z.string().min(1),
              source: z.string().default("manual"),
              createdAt: z.string().optional(),
              updatedAt: z.string().optional(),
            })
          )
          .default([]),
      })
    )
    .mutation(({ input, ctx }) => {
      const now = new Date().toISOString();

      return db.transaction((tx) => {
        // localId (clientRef) → serverId for each table.
        const chapterMap: Record<string, string> = {};
        const todoMap: Record<string, string> = {};
        const decisionMap: Record<string, string> = {};
        const entryMap: Record<string, string> = {};

        /** Upsert by (userId, clientRef): a re-run resolves to the same server id. */
        const resolveChapter = (clientRef: string): string => {
          const existing = tx
            .select({ id: chapters.id })
            .from(chapters)
            .where(and(eq(chapters.userId, ctx.userId), eq(chapters.clientRef, clientRef)))
            .get();
          return existing?.id ?? randomUUID();
        };

        // 1) Chapters first — children resolve their parent FK against this map.
        for (const c of input.chapters) {
          const id = resolveChapter(c.clientRef);
          chapterMap[c.clientRef] = id;
          tx.insert(chapters)
            .values({
              id,
              userId: ctx.userId,
              clientRef: c.clientRef,
              title: c.title,
              type: c.type as never,
              status: c.status as never,
              startDate: c.startDate ?? null,
              endDate: c.endDate ?? null,
              purpose: c.purpose ?? null,
              createdAt: c.createdAt ?? now,
              updatedAt: c.updatedAt ?? now,
            })
            // Idempotent re-run: the (userId, clientRef) row already exists → no-op.
            .onConflictDoNothing()
            .run();
        }

        // Resolve a child's parent: prefer a chapter uploaded in THIS call, else
        // an already-synced chapter whose clientRef == chapterRef (re-run), else
        // treat chapterRef as an already-server chapter id (canonical lowercase).
        const resolveParent = (chapterRef: string): string => {
          if (chapterMap[chapterRef]) return chapterMap[chapterRef];
          const byRef = tx
            .select({ id: chapters.id })
            .from(chapters)
            .where(and(eq(chapters.userId, ctx.userId), eq(chapters.clientRef, chapterRef)))
            .get();
          return byRef?.id ?? canonicalId(chapterRef);
        };

        // 2) Todos
        for (const t of input.todos) {
          const existing = tx
            .select({ id: todos.id })
            .from(todos)
            .where(and(eq(todos.userId, ctx.userId), eq(todos.clientRef, t.clientRef)))
            .get();
          const id = existing?.id ?? randomUUID();
          todoMap[t.clientRef] = id;
          tx.insert(todos)
            .values({
              id,
              userId: ctx.userId,
              clientRef: t.clientRef,
              chapterId: resolveParent(t.chapterRef),
              text: t.text,
              done: t.done,
              dueDate: t.dueDate ?? null,
              source: t.source as never,
              createdAt: t.createdAt ?? now,
              updatedAt: t.updatedAt ?? now,
            })
            .onConflictDoNothing()
            .run();
        }

        // 3) Decisions
        for (const d of input.decisions) {
          const existing = tx
            .select({ id: decisions.id })
            .from(decisions)
            .where(and(eq(decisions.userId, ctx.userId), eq(decisions.clientRef, d.clientRef)))
            .get();
          const id = existing?.id ?? randomUUID();
          decisionMap[d.clientRef] = id;
          tx.insert(decisions)
            .values({
              id,
              userId: ctx.userId,
              clientRef: d.clientRef,
              chapterId: resolveParent(d.chapterRef),
              title: d.title,
              rationale: d.rationale ?? null,
              optionsConsidered: d.optionsConsidered ?? null,
              decidedAt: d.decidedAt,
              source: d.source as never,
              createdAt: d.createdAt ?? now,
              updatedAt: d.updatedAt ?? now,
            })
            .onConflictDoNothing()
            .run();
        }

        // 4) Entries
        for (const e of input.entries) {
          const existing = tx
            .select({ id: entries.id })
            .from(entries)
            .where(and(eq(entries.userId, ctx.userId), eq(entries.clientRef, e.clientRef)))
            .get();
          const id = existing?.id ?? randomUUID();
          entryMap[e.clientRef] = id;
          tx.insert(entries)
            .values({
              id,
              userId: ctx.userId,
              clientRef: e.clientRef,
              chapterId: resolveParent(e.chapterRef),
              date: e.date,
              content: e.content,
              source: e.source as never,
              createdAt: e.createdAt ?? now,
              updatedAt: e.updatedAt ?? now,
            })
            .onConflictDoNothing()
            .run();
        }

        // The client rewrites its local ids (and child FKs) using these maps,
        // then permanently stops local generation for synced types (§4.d).
        return {
          mapping: {
            chapters: chapterMap,
            todos: todoMap,
            decisions: decisionMap,
            entries: entryMap,
          },
          serverTime: now,
        };
      });
    }),
});
