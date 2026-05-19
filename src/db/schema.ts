import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";
import { relations, sql } from "drizzle-orm";

export const chapterTypes = [
  "trip",
  "move",
  "project",
  "launch",
  "recurring",
  "personal",
] as const;
export type ChapterType = (typeof chapterTypes)[number];

export const chapterStatuses = ["upcoming", "active", "paused", "done"] as const;
export type ChapterStatus = (typeof chapterStatuses)[number];

export const linkRelations = ["blocks", "enables", "conflicts", "related"] as const;
export type LinkRelation = (typeof linkRelations)[number];

export const entrySources = ["manual", "email", "calendar", "drive"] as const;
export type EntrySource = (typeof entrySources)[number];

export const todoSources = ["manual", "extracted"] as const;
export type TodoSource = (typeof todoSources)[number];

export const chapters = sqliteTable("chapters", {
  id: text("id").primaryKey(),
  title: text("title").notNull(),
  type: text("type", { enum: chapterTypes }).notNull(),
  status: text("status", { enum: chapterStatuses }).notNull().default("active"),
  startDate: text("start_date"),
  endDate: text("end_date"),
  purpose: text("purpose"),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
  updatedAt: text("updated_at").notNull().default(sql`(current_timestamp)`),
});

export const todos = sqliteTable("todos", {
  id: text("id").primaryKey(),
  chapterId: text("chapter_id")
    .notNull()
    .references(() => chapters.id, { onDelete: "cascade" }),
  text: text("text").notNull(),
  done: integer("done", { mode: "boolean" }).notNull().default(false),
  dueDate: text("due_date"),
  source: text("source", { enum: todoSources }).notNull().default("manual"),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
  doneAt: text("done_at"),
});

export const decisions = sqliteTable("decisions", {
  id: text("id").primaryKey(),
  chapterId: text("chapter_id")
    .notNull()
    .references(() => chapters.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  rationale: text("rationale"),
  optionsConsidered: text("options_considered"),
  decidedAt: text("decided_at").notNull(),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
});

export const entries = sqliteTable("entries", {
  id: text("id").primaryKey(),
  chapterId: text("chapter_id")
    .notNull()
    .references(() => chapters.id, { onDelete: "cascade" }),
  date: text("date").notNull(),
  content: text("content").notNull(),
  source: text("source", { enum: entrySources }).notNull().default("manual"),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
});

export const chapterLinks = sqliteTable(
  "chapter_links",
  {
    fromId: text("from_id")
      .notNull()
      .references(() => chapters.id, { onDelete: "cascade" }),
    toId: text("to_id")
      .notNull()
      .references(() => chapters.id, { onDelete: "cascade" }),
    relation: text("relation", { enum: linkRelations }).notNull().default("related"),
    note: text("note"),
    createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.fromId, t.toId, t.relation] }),
  })
);

export const chaptersRelations = relations(chapters, ({ many }) => ({
  todos: many(todos),
  decisions: many(decisions),
  entries: many(entries),
  linksFrom: many(chapterLinks, { relationName: "fromChapter" }),
  linksTo: many(chapterLinks, { relationName: "toChapter" }),
}));

export const todosRelations = relations(todos, ({ one }) => ({
  chapter: one(chapters, { fields: [todos.chapterId], references: [chapters.id] }),
}));

export const decisionsRelations = relations(decisions, ({ one }) => ({
  chapter: one(chapters, { fields: [decisions.chapterId], references: [chapters.id] }),
}));

export const entriesRelations = relations(entries, ({ one }) => ({
  chapter: one(chapters, { fields: [entries.chapterId], references: [chapters.id] }),
}));

export const chapterLinksRelations = relations(chapterLinks, ({ one }) => ({
  fromChapter: one(chapters, {
    fields: [chapterLinks.fromId],
    references: [chapters.id],
    relationName: "fromChapter",
  }),
  toChapter: one(chapters, {
    fields: [chapterLinks.toId],
    references: [chapters.id],
    relationName: "toChapter",
  }),
}));

export type Chapter = typeof chapters.$inferSelect;
export type NewChapter = typeof chapters.$inferInsert;
export type Todo = typeof todos.$inferSelect;
export type NewTodo = typeof todos.$inferInsert;
export type Decision = typeof decisions.$inferSelect;
export type NewDecision = typeof decisions.$inferInsert;
export type Entry = typeof entries.$inferSelect;
export type NewEntry = typeof entries.$inferInsert;
export type ChapterLink = typeof chapterLinks.$inferSelect;
export type NewChapterLink = typeof chapterLinks.$inferInsert;
