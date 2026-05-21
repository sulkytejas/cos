import { sqliteTable, text, integer, primaryKey, real } from "drizzle-orm/sqlite-core";
import { relations, sql } from "drizzle-orm";

// ─────────────────────────── enums ───────────────────────────

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

export const entrySources = ["manual", "email", "calendar", "drive", "voice"] as const;
export type EntrySource = (typeof entrySources)[number];

export const todoSources = ["manual", "extracted", "inferred"] as const;
export type TodoSource = (typeof todoSources)[number];

export const decisionSources = ["manual", "extracted", "inferred"] as const;
export type DecisionSource = (typeof decisionSources)[number];

// v0.2 enums
export const briefStatuses = ["draft", "surfaced", "dismissed", "acted_on", "archived", "failed"] as const;
export type BriefStatus = (typeof briefStatuses)[number];

export const eventTypes = [
  "chapter_created",
  "chapter_updated",
  "capture_received",
  "signal_received",
  "time_trigger",
  "watcher_due",
  "brief_acted_on",
  "daily_scan",
  "forward_drift_scan",
] as const;
export type EventType = (typeof eventTypes)[number];

export const eventStatuses = ["pending", "processing", "done", "failed"] as const;
export type EventStatus = (typeof eventStatuses)[number];

export const watcherSourceTypes = ["web", "gmail", "calendar", "drive", "internal"] as const;
export type WatcherSourceType = (typeof watcherSourceTypes)[number];

export const watcherStatuses = ["active", "paused", "completed"] as const;
export type WatcherStatus = (typeof watcherStatuses)[number];

export const signalSources = ["gmail", "calendar", "drive", "manual", "voice"] as const;
export type SignalSource = (typeof signalSources)[number];

export const proposalTypes = ["todo", "decision", "journal_entry", "chapter", "chapter_link"] as const;
export type ProposalType = (typeof proposalTypes)[number];

export const proposalStatuses = ["pending", "approved", "edited", "dismissed"] as const;
export type ProposalStatus = (typeof proposalStatuses)[number];

// ─────────────────────────── v0.1 tables (extended with provenance) ───────────────────────────

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
  // v0.2 provenance: which brief produced this, and which raw signals it was extracted from.
  sourceBriefId: text("source_brief_id"),
  sourceSignalIds: text("source_signal_ids", { mode: "json" }).$type<string[] | null>(),
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
  source: text("source", { enum: decisionSources }).notNull().default("manual"),
  sourceBriefId: text("source_brief_id"),
  sourceSignalIds: text("source_signal_ids", { mode: "json" }).$type<string[] | null>(),
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
  sourceBriefId: text("source_brief_id"),
  sourceSignalIds: text("source_signal_ids", { mode: "json" }).$type<string[] | null>(),
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
    // v0.2: is this link confirmed by the user, or proposed by Atlas?
    proposed: integer("proposed", { mode: "boolean" }).notNull().default(false),
    createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.fromId, t.toId, t.relation] }),
  })
);

// ─────────────────────────── v0.2 — the agentic surface ───────────────────────────

/**
 * A Brief — Atlas's prepared preparation document for a recognized situation.
 * The `structure` field is a JSON-encoded array of `{ component_name, props }`
 * objects validated against the BriefStructure schema in `src/lib/brief-schema.ts`.
 */
export const briefs = sqliteTable("briefs", {
  id: text("id").primaryKey(),
  chapterId: text("chapter_id").references(() => chapters.id, { onDelete: "set null" }),
  title: text("title").notNull(),
  situationDescription: text("situation_description").notNull(),
  /** JSON array of section objects — see BriefStructure schema. */
  structure: text("structure", { mode: "json" }).$type<unknown>().notNull(),
  /** Used by Brief Detail's action strip. */
  primaryAction: text("primary_action"),
  secondaryActions: text("secondary_actions", { mode: "json" }).$type<string[] | null>(),
  status: text("status", { enum: briefStatuses }).notNull().default("draft"),
  surfaceAt: text("surface_at").notNull(),
  expiresAt: text("expires_at"),
  /** Display-only — the chapter title and small relevance tag the design shows. */
  chapterTitle: text("chapter_title"),
  relevance: text("relevance"),
  when: text("when"),
  drafted: text("drafted"),
  preview: text("preview"),
  /** JSON trace of tool calls + reasoning. Inspect for debugging. */
  agentTrace: text("agent_trace", { mode: "json" }).$type<unknown>(),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
});

/**
 * Events — the queue between the web app and the worker. The app writes here;
 * the worker polls, processes, and marks `status='done' | 'failed'`.
 */
export const events = sqliteTable("events", {
  id: text("id").primaryKey(),
  type: text("type", { enum: eventTypes }).notNull(),
  payload: text("payload", { mode: "json" }).$type<unknown>().notNull(),
  status: text("status", { enum: eventStatuses }).notNull().default("pending"),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
  processedAt: text("processed_at"),
  error: text("error"),
});

/**
 * Watchers — Atlas's standing instructions to itself. Each row says
 * "re-check this thing every N minutes." The worker picks watchers
 * whose `nextCheck` has elapsed.
 */
export const watchers = sqliteTable("watchers", {
  id: text("id").primaryKey(),
  chapterId: text("chapter_id").references(() => chapters.id, { onDelete: "set null" }),
  description: text("description").notNull(),
  /** What Atlas should look for / how to phrase the recheck to itself. */
  prompt: text("prompt").notNull(),
  sourceType: text("source_type", { enum: watcherSourceTypes }).notNull().default("internal"),
  lastChecked: text("last_checked"),
  nextCheck: text("next_check").notNull(),
  cadenceMinutes: integer("cadence_minutes").notNull().default(180),
  status: text("status", { enum: watcherStatuses }).notNull().default("active"),
  lastFinding: text("last_finding", { mode: "json" }).$type<unknown>(),
  /** Short cadence label e.g. "every 3h", "on inbox" — display only. */
  cadenceLabel: text("cadence_label"),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
});

/**
 * Signals — raw external data Atlas has read in. Connectors write here,
 * the agentic worker reads when preparing briefs. `processed` indicates
 * the worker has emitted any proposals it would from this signal already.
 */
export const signals = sqliteTable("signals", {
  id: text("id").primaryKey(),
  source: text("source", { enum: signalSources }).notNull(),
  externalId: text("external_id"),
  rawData: text("raw_data", { mode: "json" }).$type<unknown>().notNull(),
  /** Short human-readable label, optional, used in the review queue UI. */
  summary: text("summary"),
  processed: integer("processed", { mode: "boolean" }).notNull().default(false),
  arrivedAt: text("arrived_at").notNull().default(sql`(current_timestamp)`),
});

/**
 * Proposals — things Atlas would like to file but isn't sure about.
 * Filed-high-confidence items are kept here too with status='approved'
 * at creation, so the Review Queue can show the "Atlas filed:" history.
 */
export const proposals = sqliteTable("proposals", {
  id: text("id").primaryKey(),
  type: text("type", { enum: proposalTypes }).notNull(),
  /** What this would become if approved. JSON; shape depends on `type`. */
  proposedPayload: text("proposed_payload", { mode: "json" }).$type<unknown>().notNull(),
  sourceBriefId: text("source_brief_id").references(() => briefs.id, { onDelete: "set null" }),
  sourceSignalIds: text("source_signal_ids", { mode: "json" }).$type<string[] | null>(),
  chapterId: text("chapter_id").references(() => chapters.id, { onDelete: "set null" }),
  status: text("status", { enum: proposalStatuses }).notNull().default("pending"),
  confidence: real("confidence").notNull().default(0.5),
  reasoning: text("reasoning"),
  /** A 1-sentence summary used in Review Queue. */
  summary: text("summary"),
  /** UI labels — source pill, e.g. "Email", and small sub-string. */
  sourceLabel: text("source_label"),
  sourceMeta: text("source_meta"),
  /** Question-shaped prompt for the user when confidence is medium/low. */
  question: text("question"),
  setup: text("setup"),
  /** JSON: array of { label, value, result } for the two-option ask. */
  options: text("options", { mode: "json" }).$type<unknown>(),
  createdAt: text("created_at").notNull().default(sql`(current_timestamp)`),
  decidedAt: text("decided_at"),
  /** If the user edited before approving, the actual approved payload. */
  decidedPayload: text("decided_payload", { mode: "json" }).$type<unknown>(),
});

/**
 * Tiny dev table — the BriefRenderer logs here when it encounters a
 * component_name not in its registry, so we know what Atlas wanted but
 * we hadn't built yet.
 */
export const devUnknownComponents = sqliteTable("dev_unknown_components", {
  id: text("id").primaryKey(),
  briefId: text("brief_id"),
  componentName: text("component_name").notNull(),
  rawProps: text("raw_props", { mode: "json" }).$type<unknown>(),
  loggedAt: text("logged_at").notNull().default(sql`(current_timestamp)`),
});

// ─────────────────────────── relations ───────────────────────────

export const chaptersRelations = relations(chapters, ({ many }) => ({
  todos: many(todos),
  decisions: many(decisions),
  entries: many(entries),
  linksFrom: many(chapterLinks, { relationName: "fromChapter" }),
  linksTo: many(chapterLinks, { relationName: "toChapter" }),
  briefs: many(briefs),
  watchers: many(watchers),
  proposals: many(proposals),
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

export const briefsRelations = relations(briefs, ({ one, many }) => ({
  chapter: one(chapters, { fields: [briefs.chapterId], references: [chapters.id] }),
  proposals: many(proposals),
}));

export const watchersRelations = relations(watchers, ({ one }) => ({
  chapter: one(chapters, { fields: [watchers.chapterId], references: [chapters.id] }),
}));

export const proposalsRelations = relations(proposals, ({ one }) => ({
  chapter: one(chapters, { fields: [proposals.chapterId], references: [chapters.id] }),
  sourceBrief: one(briefs, { fields: [proposals.sourceBriefId], references: [briefs.id] }),
}));

// ─────────────────────────── inferred types ───────────────────────────

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

export type Brief = typeof briefs.$inferSelect;
export type NewBrief = typeof briefs.$inferInsert;
export type Event = typeof events.$inferSelect;
export type NewEvent = typeof events.$inferInsert;
export type Watcher = typeof watchers.$inferSelect;
export type NewWatcher = typeof watchers.$inferInsert;
export type Signal = typeof signals.$inferSelect;
export type NewSignal = typeof signals.$inferInsert;
export type Proposal = typeof proposals.$inferSelect;
export type NewProposal = typeof proposals.$inferInsert;
