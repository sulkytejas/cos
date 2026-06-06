import { sqliteTable, text, integer, primaryKey, real, uniqueIndex, index, type AnySQLiteColumn } from "drizzle-orm/sqlite-core";
import { relations, sql } from "drizzle-orm";

/**
 * ISO-8601-UTC column default (SERVER_ARCHITECTURE.md §4.d).
 *
 * SQLite's `current_timestamp` emits `YYYY-MM-DD HH:MM:SS` (a space separator),
 * while every app-level edit writes `new Date().toISOString()` =
 * `YYYY-MM-DDTHH:MM:SS.sssZ`. Lexically `' ' (0x20) < 'T' (0x54)`, so a
 * string-compare sync cursor over a mix of both is NON-monotonic and silently
 * skips rows. We therefore default in the SAME ISO-8601-UTC shape the app writes
 * (`strftime('%Y-%m-%dT%H:%M:%fZ','now')` → `2026-06-03T04:11:09.123Z`) so the
 * `(updatedAt,id)` cursor is monotonic for both default- and app-written rows.
 * The 0008 migration backfills every pre-existing space-format value to match.
 */
const ISO_NOW = sql`(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`;

/**
 * Single-tenant bootstrap owner (SERVER_ARCHITECTURE.md §4.d / §4.f).
 *
 * Every user-owned table carries a `userId` so `ctx.userId` can be threaded into
 * every query/mutation as a WHERE predicate and every insert — without it the
 * second device reads and mutates the first user's rows. v1 ships single-tenant,
 * so the column defaults to this id and the migration backfills existing rows to
 * it. This MUST match `ATLAS_USER_ID` used by the worker, `/api/ask`, and the
 * operator token seeder so worker-written rows and API-written rows share an
 * owner. Adding `userId` later would force a third migration + a risky backfill,
 * so it lands now in the same migration as `updatedAt`/`deletedAt`.
 */
export const BOOTSTRAP_USER_ID = "atlas-operator";

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
  // §4.a/§4.b (cross-process single-bucket fix): the grounded Ask is NOT run
  // inline in Next.js — it is enqueued as a `one_shot` job the worker drains, so
  // only the worker process ever calls messages.create and the in-memory token
  // bucket stays authoritative. The client polls `event.status(jobId)` and reads
  // the answer + resultProposalIds off the done-status `result`.
  "ai_ask",
  // Capture co-completion (PART 1 / Module MC). Same single-bucket discipline as
  // `ai_ask`: the well's `complete({fragment})` does NOT call the gateway inline —
  // it enqueues a `capture_complete` `one_shot` job the WORKER drains (Haiku, low
  // latency), producing the ghost completion + kind/chapter classification. The
  // result `{ghost,kind,chapterId,question,confidence}` is written to
  // `events.result`; the router polls `events.status` and returns it to the well.
  "capture_complete",
  // Memory layer (build plan W2–W4): once per day, after the morning work
  // finishes, this job drafts notes from what the run read/wrote (extract),
  // reconciles them against the notebook (consolidate: ADD / REINFORCE /
  // SUPERSEDE / DROP), and rewrites the one-page digest. Enqueued with a
  // `memory_consolidate:<YYYY-MM-DD>` dedupeKey so boot + timer + catch-up
  // collapse to one run per day. Phase 0 lands the type; the handler is wired
  // in Phase 2.
  "memory_consolidate",
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

/**
 * Turn roles (Today agentic flow v1). The Today screen is a real conversational
 * thread backed by the `turns` table — `ayumi` is the agent's voice, `user` is
 * the operator's own message back into the thread.
 */
export const turnRoles = ["ayumi", "user"] as const;
export type TurnRole = (typeof turnRoles)[number];

/**
 * Turn kinds. `morning` is the daily-scan turn (a verdict on Today + a
 * redlineable memo in Review); `message` is an ordinary conversational line;
 * `thinking` is the transient "reading the deck…" beat shown while Ayumi works.
 */
export const turnKinds = ["morning", "message", "thinking"] as const;
export type TurnKind = (typeof turnKinds)[number];

/**
 * Observation kinds (memory layer Phase 0 — designs/Atlas Memory Layer build
 * plan §1). Coarse buckets only — the note BODY is free-form on principle ("he
 * goes quiet before big asks" is a perfectly good note); the kind just lets the
 * digest builder group "habits" apart from "what's going on right now".
 *
 * `prediction` (Memory v2, slice P): a falsifiable bet with a numeric
 * confidence and a resolve-by date — "Karan replies about the deck by
 * Thursday". Predictions are the loop that makes the notebook EVOLVE: outcomes
 * flow back along `basedOnIds` (confirmed → backing notes reinforce; refuted →
 * they weaken), so knowing-someone becomes measurable (calibration) instead of
 * an archive.
 */
export const observationKinds = [
  "fact",
  "preference",
  "pattern",
  "relationship",
  "state",
  "prediction",
] as const;
export type ObservationKind = (typeof observationKinds)[number];

/** How reality graded a prediction. NULL until its resolve-by date passes. */
export const observationOutcomes = ["confirmed", "refuted", "unresolved"] as const;
export type ObservationOutcome = (typeof observationOutcomes)[number];

/**
 * How the note came to be believed: saw it happen in the signals, was told by the
 * user, or inferred. Paired with `confidence` (0–1, like proposals).
 */
export const observationSources = ["observed", "told", "inferred"] as const;
export type ObservationSource = (typeof observationSources)[number];

// ─────────────────────────── v0.1 tables (extended with provenance) ───────────────────────────

export const chapters = sqliteTable(
  "chapters",
  {
    id: text("id").primaryKey(),
    /** Owning user — threaded into every query/mutation as a WHERE predicate (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    title: text("title").notNull(),
    type: text("type", { enum: chapterTypes }).notNull(),
    status: text("status", { enum: chapterStatuses }).notNull().default("active"),
    startDate: text("start_date"),
    endDate: text("end_date"),
    purpose: text("purpose"),
    /**
     * Advisory `palette` (Today agentic flow v1): a vocabulary of component
     * kinds from the library this chapter's life is likely to need, emitted by
     * the worker on chapter_created/chapter_updated runs. NOT a template — it's a
     * hint the renderer/agent can draw from. JSON array of kind names, null until
     * a chapter touch has been processed.
     */
    palette: text("palette", { mode: "json" }).$type<string[] | null>(),
    /**
     * §4.d idempotent replay / optimistic reconciliation: a client-minted UUID
     * carried on create. A retried chapter create with the same `clientRef`
     * upserts the same row, and the client reconciles its optimistic local row
     * against the server id by matching `clientRef`. Also the unit `sync.bootstrap`
     * uses to map a local-only chapter's old id to its assigned server id.
     */
    clientRef: text("client_ref"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    updatedAt: text("updated_at").notNull().default(ISO_NOW),
    /** Soft-delete tombstone (§4.d). Reads filter `deletedAt IS NULL`; a pull-by-cursor mirror observes the tombstone instead of a vanished row. */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("chapters_user_idx").on(t.userId),
    // §4.d: one chapter per (userId, clientRef) so a replayed create / a
    // re-run bootstrap upload can't duplicate.
    clientRefUnq: uniqueIndex("chapters_user_client_ref_unq")
      .on(t.userId, t.clientRef)
      .where(sql`${t.clientRef} IS NOT NULL`),
  })
);

export const todos = sqliteTable(
  "todos",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
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
    /**
     * §4.d push-idempotency: the proposal whose approval filed this todo. UNIQUE
     * (per the partial index below), so `proposal.approve → writePayload`'s
     * `INSERT … ON CONFLICT(source_proposal_id) DO NOTHING` collapses an
     * at-least-once outbox retry to a single filed todo. NULL for user/agent
     * todos that didn't come from a proposal (the partial index leaves those
     * freely insertable).
     */
    sourceProposalId: text("source_proposal_id"),
    /**
     * §4.d idempotent replay & optimistic-row reconciliation: a client-minted
     * UUID carried on create. A retried create with the same `clientRef` upserts
     * the same row instead of inserting a duplicate, and the client reconciles
     * its optimistic local row against the server id by matching `clientRef`.
     * NULL for server/agent-originated rows.
     */
    clientRef: text("client_ref"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation so a cursor-by-`updatedAt` sync can't miss an edit (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
    doneAt: text("done_at"),
  },
  (t) => ({
    userIdx: index("todos_user_idx").on(t.userId),
    // §4.d: one filed todo per source proposal. Partial — unique only over rows
    // that carry a source proposal (most user/agent todos do not).
    sourceProposalUnq: uniqueIndex("todos_source_proposal_unq")
      .on(t.sourceProposalId)
      .where(sql`${t.sourceProposalId} IS NOT NULL`),
    // §4.d: one row per (userId, clientRef) so a replayed create can't duplicate.
    clientRefUnq: uniqueIndex("todos_user_client_ref_unq")
      .on(t.userId, t.clientRef)
      .where(sql`${t.clientRef} IS NOT NULL`),
  })
);

export const decisions = sqliteTable(
  "decisions",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
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
    /** §4.d push-idempotency: the proposal whose approval filed this decision. UNIQUE (partial index below) → one decision per source proposal under outbox retry. */
    sourceProposalId: text("source_proposal_id"),
    /** §4.d idempotent replay / optimistic reconciliation: client-minted UUID carried on create. */
    clientRef: text("client_ref"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation (§4.d). ISO-8601 UTC via `$defaultFn` so seeds and any insert that omits it still get a monotonic timestamp (not the migration's constant ALTER default). */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("decisions_user_idx").on(t.userId),
    sourceProposalUnq: uniqueIndex("decisions_source_proposal_unq")
      .on(t.sourceProposalId)
      .where(sql`${t.sourceProposalId} IS NOT NULL`),
    clientRefUnq: uniqueIndex("decisions_user_client_ref_unq")
      .on(t.userId, t.clientRef)
      .where(sql`${t.clientRef} IS NOT NULL`),
  })
);

export const entries = sqliteTable(
  "entries",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    chapterId: text("chapter_id")
      .notNull()
      .references(() => chapters.id, { onDelete: "cascade" }),
    date: text("date").notNull(),
    content: text("content").notNull(),
    source: text("source", { enum: entrySources }).notNull().default("manual"),
    sourceBriefId: text("source_brief_id"),
    sourceSignalIds: text("source_signal_ids", { mode: "json" }).$type<string[] | null>(),
    /** §4.d push-idempotency: the proposal whose approval filed this entry. UNIQUE (partial index below) → one entry per source proposal under outbox retry. */
    sourceProposalId: text("source_proposal_id"),
    /** §4.d idempotent replay / optimistic reconciliation: client-minted UUID carried on create. */
    clientRef: text("client_ref"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation (§4.d). ISO-8601 UTC via `$defaultFn` so seeds and any insert that omits it still get a monotonic timestamp (not the migration's constant ALTER default). */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("entries_user_idx").on(t.userId),
    sourceProposalUnq: uniqueIndex("entries_source_proposal_unq")
      .on(t.sourceProposalId)
      .where(sql`${t.sourceProposalId} IS NOT NULL`),
    clientRefUnq: uniqueIndex("entries_user_client_ref_unq")
      .on(t.userId, t.clientRef)
      .where(sql`${t.clientRef} IS NOT NULL`),
  })
);

export const chapterLinks = sqliteTable(
  "chapter_links",
  {
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
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
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation (§4.d). ISO-8601 UTC via `$defaultFn` so seeds and any insert that omits it still get a monotonic timestamp (not the migration's constant ALTER default). */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). The `(fromId|toId|relation)` PK is the synthetic sync key. */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.fromId, t.toId, t.relation] }),
    userIdx: index("chapter_links_user_idx").on(t.userId),
  })
);

// ─────────────────────────── v0.2 — the agentic surface ───────────────────────────

/**
 * A Brief — Atlas's prepared preparation document for a recognized situation.
 * The `structure` field is a JSON-encoded array of `{ component_name, props }`
 * objects validated against the BriefStructure schema in `src/lib/brief-schema.ts`.
 */
export const briefs = sqliteTable(
  "briefs",
  {
  id: text("id").primaryKey(),
  /** Owning user (§4.d/§4.f). */
  userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
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
  /**
   * The event whose agent run produced this brief. On crash-recovery the
   * worker deletes prior output of a requeued event before re-running, so a
   * kill mid-`daily_scan` can't double the "drafted while you slept" briefs.
   */
  generatedByEventId: text("generated_by_event_id"),
  createdAt: text("created_at").notNull().default(ISO_NOW),
  /** Bumped on every mutation — e.g. `brief.setStatus` (Start/Snooze) (§4.d). ISO-8601 UTC via `$defaultFn`. */
  updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
  /** Soft-delete tombstone (§4.d). */
  deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("briefs_user_idx").on(t.userId),
  })
);

/**
 * Events — the queue between the web app and the worker. The app writes here;
 * the worker polls, processes, and marks `status='done' | 'failed'`.
 */
export const events = sqliteTable(
  "events",
  {
    id: text("id").primaryKey(),
    /** Owning user — every intent the worker processes is scoped to its emitter (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    type: text("type", { enum: eventTypes }).notNull(),
    payload: text("payload", { mode: "json" }).$type<unknown>().notNull(),
    status: text("status", { enum: eventStatuses }).notNull().default("pending"),
    /**
     * Set when a worker claims this row (status -> processing). The watchdog
     * reclaims rows whose claim is older than STUCK_MS; the running agent
     * heartbeats this column so a slow-but-alive run is never reclaimed.
     */
    claimedAt: text("claimed_at"),
    /** Incremented on each claim. Drives the MAX_ATTEMPTS retry ceiling. */
    attempts: integer("attempts").notNull().default(0),
    /**
     * Optional idempotency key for *enqueue* dedup (e.g. `daily_scan:2026-05-31`).
     * A unique partial index (below) lets the scheduler enqueue-once safely:
     * an INSERT … ON CONFLICT(dedupeKey) DO NOTHING collapses concurrent
     * boot + timer + catch-up attempts to a single row.
     */
    dedupeKey: text("dedupe_key"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped when the worker claims/marks the event (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
    processedAt: text("processed_at"),
    error: text("error"),
    /**
     * Job result, set in the SAME txn as `status='done'` by the worker's commit
     * phase (§4.a/§4.b). Today only `ai_ask` writes here: `{ answer,
     * resultProposalIds }`. The client polls `event.status(jobId)` and, on
     * `done`, reads this off the status response — so the grounded Ask round-trips
     * through the queue (single authoritative bucket) instead of an inline
     * Anthropic call in Next.js. JSON; null for event types that persist their
     * output elsewhere (briefs/proposals tables).
     */
    result: text("result", { mode: "json" }).$type<unknown>(),
  },
  (t) => ({
    // Unique only over non-NULL keys — most events (captures, signals) carry no
    // dedupeKey and must remain insertable freely.
    dedupeKeyUnq: uniqueIndex("events_dedupe_key_unq")
      .on(t.dedupeKey)
      .where(sql`${t.dedupeKey} IS NOT NULL`),
    // Hot path for the atomic claim: WHERE status='pending' ORDER BY createdAt.
    statusCreatedIdx: index("events_status_created_idx").on(t.status, t.createdAt),
    userIdx: index("events_user_idx").on(t.userId),
  }),
);

/**
 * Watchers — Atlas's standing instructions to itself. Each row says
 * "re-check this thing every N minutes." The worker picks watchers
 * whose `nextCheck` has elapsed.
 */
export const watchers = sqliteTable(
  "watchers",
  {
  id: text("id").primaryKey(),
  /** Owning user (§4.d/§4.f). */
  userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
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
  createdAt: text("created_at").notNull().default(ISO_NOW),
  /** Bumped on every mutation — reschedule, pause, completion (§4.d). ISO-8601 UTC via `$defaultFn`. */
  updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
  /** Soft-delete tombstone (§4.d). */
  deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("watchers_user_idx").on(t.userId),
  })
);

/**
 * Signals — raw external data Atlas has read in. Connectors write here,
 * the agentic worker reads when preparing briefs. `processed` indicates
 * the worker has emitted any proposals it would from this signal already.
 */
export const signals = sqliteTable(
  "signals",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    source: text("source", { enum: signalSources }).notNull(),
    externalId: text("external_id"),
    rawData: text("raw_data", { mode: "json" }).$type<unknown>().notNull(),
    /** Short human-readable label, optional, used in the review queue UI. */
    summary: text("summary"),
    processed: integer("processed", { mode: "boolean" }).notNull().default(false),
    arrivedAt: text("arrived_at").notNull().default(ISO_NOW),
    /** Bumped when the worker marks the signal processed (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("signals_user_idx").on(t.userId),
    /**
     * §4.e: iOS pushes its EventKit calendar on every foreground via
     * `signal.ingest`, which upserts on `(userId, source, externalId)` so a
     * re-push of the same calendar event doesn't create a duplicate signal.
     * Scoped by `userId` too, so two users' calendars with a colliding
     * `externalId` (EKEvent.eventIdentifier) never clobber each other. Partial:
     * unique only when `externalId` is present — agent/connector signals without
     * an external id (e.g. coalesced internal signals) stay freely insertable.
     */
    externalIdUnq: uniqueIndex("signals_user_source_external_unq")
      .on(t.userId, t.source, t.externalId)
      .where(sql`${t.externalId} IS NOT NULL`),
  })
);

/**
 * Proposals — things Atlas would like to file but isn't sure about.
 * Filed-high-confidence items are kept here too with status='approved'
 * at creation, so the Review Queue can show the "Atlas filed:" history.
 */
export const proposals = sqliteTable(
  "proposals",
  {
  id: text("id").primaryKey(),
  /** Owning user (§4.d/§4.f). */
  userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
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
  createdAt: text("created_at").notNull().default(ISO_NOW),
  /** Bumped on approve/dismiss/edit (§4.d). ISO-8601 UTC via `$defaultFn`. */
  updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
  /** Soft-delete tombstone (§4.d). */
  deletedAt: text("deleted_at"),
  decidedAt: text("decided_at"),
  /** If the user edited before approving, the actual approved payload. */
  decidedPayload: text("decided_payload", { mode: "json" }).$type<unknown>(),
  /** See briefs.generatedByEventId — recovery deletes a requeued event's prior output. */
  generatedByEventId: text("generated_by_event_id"),
  },
  (t) => ({
    userIdx: index("proposals_user_idx").on(t.userId),
  })
);

/**
 * Turns — the Today screen's conversational thread (Today agentic flow v1).
 *
 * The worker's daily_scan composes a "morning turn": a 1-2 sentence VERDICT
 * (`body`, shown on Today) plus a full `memo` (redlineable in Review — the user
 * strikes lines, then "keeps" it). Voice rules live in the worker prompt; every
 * sentence's subject is the user's world, never the agent's process. The morning
 * turn may carry ONE `connector` suggestion (only when a concrete observed gap
 * exists). User messages and transient `thinking` beats ride the same table so
 * the thread renders from one ordered query.
 *
 * Pattern-matched to `briefs` exactly for userId / timestamps / tombstone so it
 * rides the SAME `(updatedAt, id)` delta-sync cursor to the iOS mirror (it is
 * registered in `sync.ts` ID_TABLES, like briefs).
 */
export const turns = sqliteTable(
  "turns",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    role: text("role", { enum: turnRoles }).notNull(),
    kind: text("kind", { enum: turnKinds }).notNull().default("message"),
    /** The rendered body (markup grammar: `*roman*`, `==accent==`, else italic). For a morning turn this is the verdict. */
    body: text("body").notNull(),
    /** Short provenance label, e.g. "6 sources · email, voice memo, calendar, deck v3". Display only. */
    sourceTag: text("source_tag"),
    /** Briefs this turn embeds as capsules in the thread. */
    briefIds: text("brief_ids", { mode: "json" }).$type<string[] | null>(),
    /**
     * The redlineable memo (morning turns only). Each line is a disposition the
     * user can strike; striking a `proposal`-ref line dismisses that proposal.
     * `status` flips draft → kept on "keep" (or auto-seal of a stale draft).
     */
    memo: text("memo", { mode: "json" }).$type<{
      lines: Array<{
        id: string;
        text: string;
        refKind: "brief" | "proposal" | null;
        refId: string | null;
        struck: boolean;
        /**
         * Memory layer Phase 5.1: the notebook notes this line leaned on.
         * Striking the line marks them struck — the red pen reaches the
         * notebook. Optional so every pre-existing memo keeps working; iOS
         * Codable ignores the unknown key.
         */
        noteIds?: string[] | null;
        /**
         * Word-level redline (the finer pen): indices of struck WORDS in the
         * line's display tokenization (markup stripped, whitespace-split).
         * A partial strike is a PUT — the line stays alive with its struck
         * spans recorded; only a FULL strike (`struck: true`) fires the
         * forget/dismiss effects. Word indices, not char offsets, so markup
         * parsing differences can never skew the meaning. Optional — every
         * pre-existing memo line decodes unchanged.
         */
        struckWords?: number[] | null;
      }>;
      status: "draft" | "kept";
      keptAt: string | null;
      keptBy: "user" | "auto" | null;
    } | null>(),
    /** At most one connector suggestion — only emitted on a concrete observed gap. */
    connector: text("connector", { mode: "json" }).$type<{
      source: "gmail" | "calendar" | "drive";
      copy: string;
    } | null>(),
    /** The overnight window this morning turn covers, for the "while you slept" divider. */
    meta: text("meta", { mode: "json" }).$type<{
      windowStart: string;
      windowEnd: string;
    } | null>(),
    /** See briefs.generatedByEventId — recovery deletes a requeued event's prior output. */
    generatedByEventId: text("generated_by_event_id"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation — strike/keep/auto-seal (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("turns_user_idx").on(t.userId),
  })
);

/**
 * Usage ledger — the per-user/day token budget the AI gateway enforces and
 * persists (SERVER_ARCHITECTURE.md §4.b). One row per (userId, day). The budget
 * is defined against `input + cache_creation + output` ONLY — free
 * `cache_read_input_tokens` are excluded (porting the iOS number but fixing its
 * accounting). The gateway reads/updates this so the budget survives a worker
 * restart, and refuses calls once `chargeableTokens >= perUserDailyTokenCap`.
 */
export const usageLedger = sqliteTable(
  "usage_ledger",
  {
    /** Synthetic id; the real key is the (userId, day) unique index below. */
    id: text("id").primaryKey(),
    /** Owning user. */
    userId: text("user_id").notNull(),
    /** Local day bucket, `YYYY-MM-DD`. */
    day: text("day").notNull(),
    /** Tokens that count against the budget: input + cache_creation + output. */
    chargeableTokens: integer("chargeable_tokens").notNull().default(0),
    /** Uncached input tokens charged (input_tokens). */
    inputTokens: integer("input_tokens").notNull().default(0),
    /** Cache-write tokens charged (cache_creation_input_tokens). */
    cacheCreationTokens: integer("cache_creation_tokens").notNull().default(0),
    /** Free cache reads — tracked for observability, NOT counted in the budget. */
    cacheReadTokens: integer("cache_read_tokens").notNull().default(0),
    /** Output tokens charged. */
    outputTokens: integer("output_tokens").notNull().default(0),
    /** How many gateway calls landed against this row. */
    requests: integer("requests").notNull().default(0),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    updatedAt: text("updated_at").notNull().default(ISO_NOW),
  },
  (t) => ({
    userDay: uniqueIndex("usage_ledger_user_day_idx").on(t.userId, t.day),
  })
);

/**
 * Device tokens — the auth credential the keyless iOS client carries
 * (SERVER_ARCHITECTURE.md §4.f, §4.d). One row per issued device token.
 *
 * SECURITY: we store ONLY `tokenHash = sha256(token + AUTH_TOKEN_PEPPER)`, never
 * the plaintext token. A plaintext-PK token table would hand out live
 * credentials on any DB or backup leak (litestream replicates the DB to a second
 * location), so the resolution is hashing. The plaintext is shown exactly once,
 * at mint time, to the operator (see src/db/seed-token.ts) and is unrecoverable
 * afterward.
 *
 * The bearer header is resolved to a `userId` in `createContext`
 * (src/server/trpc.ts): hash the presented token the same way, look up the row,
 * and reject absent/unknown/revoked tokens with TRPCError UNAUTHORIZED. There is
 * NO `DEFAULT_USER_ID` fail-open anywhere.
 *
 * Single-tenant MVP: open `register` is disabled; the one operator token is
 * seeded at deploy time via `tsx src/db/seed-token.ts`.
 */
export const deviceTokens = sqliteTable(
  "device_tokens",
  {
    id: text("id").primaryKey(),
    /** Owning user — threaded into every query/mutation as a WHERE predicate. */
    userId: text("user_id").notNull(),
    /**
     * sha256(token + AUTH_TOKEN_PEPPER), lowercase hex. The unique index makes a
     * presented-token lookup a single indexed equality probe and forbids two rows
     * resolving to the same credential.
     */
    tokenHash: text("token_hash").notNull(),
    /** Human label for the device, e.g. "operator-iphone". */
    label: text("label").notNull().default("device"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every authenticated request that resolves to this token. */
    lastSeenAt: text("last_seen_at"),
    /** Set to revoke: a revoked token resolves to UNAUTHORIZED. NULL = active. */
    revokedAt: text("revoked_at"),
  },
  (t) => ({
    tokenHashIdx: uniqueIndex("device_tokens_token_hash_idx").on(t.tokenHash),
    userIdx: index("device_tokens_user_idx").on(t.userId),
  })
);

/**
 * Connector backpressure cursor (SERVER_ARCHITECTURE.md §4.c) — PER USER.
 *
 * One row per `(userId, source)`. `cursor` is the position the poller has reached
 * in the upstream feed: for the fixtures, the index into the fixture array; for a
 * real Gmail/Calendar/Drive connector, the page token / historyId / sync token.
 * Capping each `pollOnce` at MAX_SIGNALS_PER_POLL and advancing this cursor lets a
 * first-time backfill of hundreds of threads drain over many polls instead of
 * flooding the queue and exhausting the per-user daily budget before morning.
 * Persisted so the cap survives a worker restart mid-backfill.
 *
 * §4.f Phase 5 made this per-user: with real OAuth each user has an independent
 * upstream cursor, so the key is composite. The `0009` migration backfills every
 * pre-existing single-tenant row to `BOOTSTRAP_USER_ID`.
 */
export const connectorState = sqliteTable(
  "connector_state",
  {
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** The connector source. */
    source: text("source", { enum: signalSources }).notNull(),
    /** Position reached in the upstream feed (fixture index / page token / historyId). */
    cursor: text("cursor").notNull().default("0"),
    updatedAt: text("updated_at").notNull().default(ISO_NOW),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.userId, t.source] }),
  }),
);

/**
 * Connector OAuth accounts (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * One row per `(userId, source)`: the long-lived Google OAuth grant for a real
 * Gmail / Calendar / Drive connection. The **refresh token is encrypted at rest**
 * with AES-256-GCM (`worker/src/connectors/crypto.ts`) using a key from
 * `CONNECTOR_ENCRYPTION_KEY` in /etc/atlas/atlas.env — the key is NEVER in the
 * DB, and the owning `userId` is bound as GCM AAD, so a ciphertext copied between
 * users' rows fails to decrypt. Only ciphertext + per-message IV + auth tag are
 * persisted, so litestream replicates nothing sensitive in the clear.
 *
 * The short-lived access token is deliberately NOT stored — the poller mints a
 * fresh one from the refresh token each poll (Google access tokens live ~1h; a
 * 15-min poll would re-fetch anyway), keeping the high-value secret surface to
 * just the encrypted refresh token.
 */
export const connectorAccounts = sqliteTable(
  "connector_accounts",
  {
    id: text("id").primaryKey(),
    /** Owning user — threaded into every query/mutation as a WHERE predicate. */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** Which connector this grant powers. */
    source: text("source", { enum: signalSources }).notNull(),
    /** The Google account email this grant belongs to (for display + dedupe). */
    accountEmail: text("account_email"),
    /** AES-256-GCM ciphertext of the refresh token (base64). */
    refreshTokenCiphertext: text("refresh_token_ciphertext").notNull(),
    /** base64 96-bit IV used to seal `refreshTokenCiphertext`. */
    refreshTokenIv: text("refresh_token_iv").notNull(),
    /** base64 128-bit GCM auth tag for `refreshTokenCiphertext`. */
    refreshTokenTag: text("refresh_token_tag").notNull(),
    /** Space-separated OAuth scopes the grant covers. */
    scope: text("scope"),
    /**
     * Opaque upstream incremental-sync cursor for the REAL OAuth path: Gmail's
     * `historyId`, Calendar's `syncToken`, or Drive Changes' `pageToken`. NULL on
     * first connect → the next poll does a bounded initial backfill and records
     * the new cursor. (Distinct from `connector_state.cursor`, which is the
     * integer fixture-array index used only by the demo path.)
     */
    syncCursor: text("sync_cursor"),
    /**
     * 'active' = polling; 'revoked' = user disconnected or the grant was
     * invalidated upstream (refresh failed with invalid_grant) — the poller skips
     * it and the UI prompts re-auth. NULL deletedAt; soft-delete on disconnect.
     */
    status: text("status").notNull().default("active"),
    /** Last successful poll (observability). */
    lastPolledAt: text("last_polled_at"),
    /** Last error message from a failed refresh/poll (observability + re-auth UI). */
    lastError: text("last_error"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone — set on disconnect (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    /** One live grant per (user, source); re-connecting upserts onto it. */
    userSourceUnq: uniqueIndex("connector_accounts_user_source_unq").on(t.userId, t.source),
    userIdx: index("connector_accounts_user_idx").on(t.userId),
  }),
);

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
  loggedAt: text("logged_at").notNull().default(ISO_NOW),
});

// ─────────────────────────── v0.7 — the Living Chapter (trip) ───────────────────────────

/**
 * Per-user mutable overlay on a seeded trip/chapter (design handoff PART 2).
 *
 * `trip.get({id})` renders a static base seed (North India — inferred from one
 * flight email) so the chapter shows OFFLINE, then applies this overlay on top so
 * the user's reconciles + connector grants PERSIST across reads. We store only the
 * deltas, not the whole trip:
 *  - `legPatches`  — `{ [legId]: { mode, fare, booked, correctedByUser } }`, the
 *    result of `correct()` ("no, I took the bus"): the leg is rewritten and the
 *    spend recomputed deterministically from the base + every applied patch.
 *  - `connectorGrants` — `{ [connectorId]: { status:'feeding', role, unlockCopy,
 *    grantedAt } }`, the result of `grantConnector()`: the source flips
 *    available→feeding and its copy is rewritten to what Ayumi can now do.
 *  - `needsRederive` — set when a grant should backfill + re-derive affected
 *    sections (spend itemisation, live seats, return planning) on the next read.
 *
 * One row per (user, trip); the procedures upsert onto it. JSON-blob overlay (not
 * a normalised leg/connector table) because the base trip is a fixed seed, not a
 * user-authored entity graph — only the corrections/grants are durable user data.
 */
export const tripState = sqliteTable(
  "trip_state",
  {
    id: text("id").primaryKey(),
    /** Owning user — every read/write is scoped to `ctx.userId` (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** The seeded trip this overlay belongs to (e.g. "north"). */
    tripId: text("trip_id").notNull(),
    /** `{ [legId]: { mode, fare, booked, correctedByUser } }` (correction patches). */
    legPatches: text("leg_patches", { mode: "json" })
      .notNull()
      .$type<Record<string, unknown>>()
      .default({}),
    /** `{ [connectorId]: { status, role, unlockCopy, grantedAt } }` (granted sources). */
    connectorGrants: text("connector_grants", { mode: "json" })
      .notNull()
      .$type<Record<string, unknown>>()
      .default({}),
    /** A granted connector marks the chapter for re-derivation on next read. */
    needsRederive: integer("needs_rederive", { mode: "boolean" }).notNull().default(false),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
  },
  (t) => ({
    /** One overlay row per (user, trip); the procedures upsert onto it. */
    userTripUnq: uniqueIndex("trip_state_user_trip_unq").on(t.userId, t.tripId),
    userIdx: index("trip_state_user_idx").on(t.userId),
  }),
);

/**
 * Durable preferences Ayumi LEARNED from a correction (design handoff §A).
 *
 * The whole point of the reconcile is that it teaches the *next* suggestion: "you
 * chose the bus over the flight — I'll lead with sleepers on your Kasol leg too."
 * `correct()` writes a row here (keyed by `prefKey`, e.g. `ground_transport`), and
 * `get()` reads it back to rewrite the *unbooked* suggestion legs' copy — so the
 * next render visibly reflects what Ayumi was taught. `weight` lets a repeated lesson
 * reinforce; `evidence` keeps the user's own words for the receipts thread.
 */
export const tripPreferences = sqliteTable(
  "trip_preferences",
  {
    id: text("id").primaryKey(),
    /** Owning user — scoped to `ctx.userId` (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** Which trip taught it (the lesson is trip-scoped for the demo). */
    tripId: text("trip_id").notNull(),
    /** The preference dimension, e.g. "ground_transport", so a re-teach upserts. */
    prefKey: text("pref_key").notNull(),
    /** The learned value, e.g. "sleeper_bus" — drives the next suggestion's copy. */
    prefValue: text("pref_value").notNull(),
    /** The human-readable "what I learned" line surfaced in the ripple toast. */
    learned: text("learned").notNull(),
    /** The user's own correction words (provenance for the receipts thread). */
    evidence: text("evidence"),
    /** Reinforcement count — a repeated lesson bumps this rather than duplicating. */
    weight: integer("weight").notNull().default(1),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
  },
  (t) => ({
    /** One row per (user, trip, dimension); a re-teach upserts + bumps weight. */
    userTripKeyUnq: uniqueIndex("trip_preferences_user_trip_key_unq").on(
      t.userId,
      t.tripId,
      t.prefKey,
    ),
    userIdx: index("trip_preferences_user_idx").on(t.userId),
  }),
);

// ─────────────────────────── v0.10 — the memory layer ───────────────────────────
// designs/Atlas Memory Layer - Today Build Plan (dev).html — Phase 0.
// Plain tables, no graph engine, no search index (locked decisions §4): the
// notebook IS rows, and the nightly digest is the only "retrieval".

/**
 * People — contact cards (build plan §1). Right now "Karan" is just text inside
 * email rows; after this he's one row that notes, briefs and lookups all point
 * at. Phase 1's matcher stays deliberately dumb (exact email match only —
 * a wrong merge makes Ayumi confidently wrong about a person), so two cards that
 * turn out to be one person are repaired by pointing one at the other via
 * `mergedIntoId` — never by deleting.
 */
export const people = sqliteTable(
  "people",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** Display name, e.g. "Karan Mohla". */
    canonicalName: text("canonical_name").notNull(),
    /** Every email address and nickname that means this person. JSON array. */
    handles: text("handles", { mode: "json" }).$type<string[]>().notNull().default([]),
    /** e.g. "Partner". */
    role: text("role"),
    /** e.g. "Sequoia India". */
    org: text("org"),
    /** When this person first / last showed up in the signals. */
    firstSeenAt: text("first_seen_at").notNull().default(ISO_NOW),
    lastSeenAt: text("last_seen_at").notNull().default(ISO_NOW),
    /** Two cards turn out to be one person? Point one at the other — don't delete. */
    mergedIntoId: text("merged_into_id").references((): AnySQLiteColumn => people.id, {
      onDelete: "set null",
    }),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("people_user_idx").on(t.userId),
  })
);

/**
 * Observations — Ayumi's notebook, one note per row (build plan §1). The body is
 * plain words ("Karan usually runs 10 minutes late"); who it concerns lives in
 * the `observationAbout` side table so "all notes about Karan" is an indexed
 * query. Old notes are never deleted, only end-dated (`invalidatedAt` +
 * `supersededById`) — that avoids the cancelled-trip-keeps-returning bug — and
 * every note must carry `receipts` so it can prove itself, note by note.
 * A "living" note is one where invalidatedAt, struckAt and deletedAt are all
 * NULL — the digest and the desk-setting read only those.
 */
export const observations = sqliteTable(
  "observations",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** The note itself, in plain words. */
    body: text("body").notNull(),
    /** Coarse bucket — the body stays free-form (no fixed list of note types). */
    kind: text("kind", { enum: observationKinds }).notNull().default("fact"),
    /** How it came to be believed: saw it / was told / guessed. */
    source: text("source", { enum: observationSources }).notNull().default("observed"),
    /** 0–1, like proposals.confidence. */
    confidence: real("confidence").notNull().default(0.5),
    /**
     * The actual emails/events that back it up — signal ids (and event ids for
     * things Ayumi wrote). A draft without receipts is thrown away, on
     * principle, so this is NOT NULL with no default: every writer must bring
     * receipts.
     */
    receipts: text("receipts", { mode: "json" }).$type<string[]>().notNull(),
    /** When life first / most recently confirmed it. */
    firstSeenAt: text("first_seen_at").notNull().default(ISO_NOW),
    lastSeenAt: text("last_seen_at").notNull().default(ISO_NOW),
    /** Reinforcement count — how often life keeps confirming it (REINFORCE bumps this). */
    weight: integer("weight").notNull().default(1),
    /** The date it stopped being true — end-dated, never deleted ("true until April"). */
    invalidatedAt: text("invalidated_at"),
    /** The newer note that replaced it (SUPERSEDE writes the new one, end-dates this one). */
    supersededById: text("superseded_by_id").references((): AnySQLiteColumn => observations.id, {
      onDelete: "set null",
    }),
    /** The red pen — user struck a memo line built on this note: forget it (F1). */
    struckAt: text("struck_at"),
    // ── Memory v2 (slice P) — prediction columns. NULL on ordinary notes. ──
    /** The notes this prediction was derived from — outcomes flow back along these (credit assignment). */
    basedOnIds: text("based_on_ids", { mode: "json" }).$type<string[] | null>(),
    /** The date by which reality settles it; the resolver only looks at due predictions. */
    resolveBy: text("resolve_by"),
    /** When the resolver judged it. */
    resolvedAt: text("resolved_at"),
    /** How reality graded it: confirmed / refuted / unresolved. */
    outcome: text("outcome", { enum: observationOutcomes }),
    /** See briefs.generatedByEventId — a requeued memory_consolidate deletes its own half-finished notes before re-running. */
    generatedByEventId: text("generated_by_event_id"),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every mutation — reinforce/supersede/strike (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    userIdx: index("observations_user_idx").on(t.userId),
  })
);

/**
 * ObservationAbout — the side table: (note id ↔ person handle) pairs, so "all
 * notes about Karan" is a fast indexed query instead of scanning text (locked
 * decision: still just data, not machinery). A note about two people gets two
 * rows — that IS the connection between them. `handle` is the raw string the
 * note named (an email address or a name); resolving handles to a `people` card
 * goes through people.handles, so a later card-merge never rewrites these rows.
 */
export const observationAbout = sqliteTable(
  "observation_about",
  {
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    observationId: text("observation_id")
      .notNull()
      .references(() => observations.id, { onDelete: "cascade" }),
    /** Who/what the note concerns — an email address or a bare name. */
    handle: text("handle").notNull(),
    createdAt: text("created_at").notNull().default(ISO_NOW),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.observationId, t.handle] }),
    /** The "all notes about Karan must be instant" index. */
    userHandleIdx: index("observation_about_user_handle_idx").on(t.userId, t.handle),
  })
);

/**
 * Digests — Ayumi's cheat sheet, one row per user, overwritten in place (build plan
 * §1, W4). Short markdown (~half a page): people · habits · preferences ·
 * what's going on right now, every line showing how many receipts back it
 * ("Karan runs late, as a rule (×4)"). Rebuilt every night from the strongest
 * living notes and pasted into every single thing Ayumi writes — don't search
 * memory, keep one short summary always in hand.
 */
export const digests = sqliteTable(
  "digests",
  {
    id: text("id").primaryKey(),
    /** Owning user (§4.d/§4.f). */
    userId: text("user_id").notNull().default(BOOTSTRAP_USER_ID),
    /** The cheat sheet itself — short markdown. */
    body: text("body").notNull(),
    /** Which notes built it — observation ids, for the receipts trail. */
    sourceObservationIds: text("source_observation_ids", { mode: "json" })
      .$type<string[]>()
      .notNull()
      .default([]),
    /** When the nightly rebuild last wrote it. */
    builtAt: text("built_at").notNull().default(ISO_NOW),
    createdAt: text("created_at").notNull().default(ISO_NOW),
    /** Bumped on every rebuild (§4.d). ISO-8601 UTC via `$defaultFn`. */
    updatedAt: text("updated_at").notNull().$defaultFn(() => new Date().toISOString()),
    /** Soft-delete tombstone (§4.d). */
    deletedAt: text("deleted_at"),
  },
  (t) => ({
    /** One cheat sheet per user; the nightly job upserts onto it. */
    userUnq: uniqueIndex("digests_user_unq").on(t.userId),
  })
);

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

export const observationsRelations = relations(observations, ({ one, many }) => ({
  about: many(observationAbout),
  supersededBy: one(observations, {
    fields: [observations.supersededById],
    references: [observations.id],
  }),
}));

export const observationAboutRelations = relations(observationAbout, ({ one }) => ({
  observation: one(observations, {
    fields: [observationAbout.observationId],
    references: [observations.id],
  }),
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
export type Turn = typeof turns.$inferSelect;
export type NewTurn = typeof turns.$inferInsert;
export type UsageLedger = typeof usageLedger.$inferSelect;
export type NewUsageLedger = typeof usageLedger.$inferInsert;
export type ConnectorState = typeof connectorState.$inferSelect;
export type NewConnectorState = typeof connectorState.$inferInsert;
export type ConnectorAccount = typeof connectorAccounts.$inferSelect;
export type NewConnectorAccount = typeof connectorAccounts.$inferInsert;
export type TripState = typeof tripState.$inferSelect;
export type NewTripState = typeof tripState.$inferInsert;
export type TripPreference = typeof tripPreferences.$inferSelect;
export type NewTripPreference = typeof tripPreferences.$inferInsert;
export type Person = typeof people.$inferSelect;
export type NewPerson = typeof people.$inferInsert;
export type Observation = typeof observations.$inferSelect;
export type NewObservation = typeof observations.$inferInsert;
export type ObservationAbout = typeof observationAbout.$inferSelect;
export type NewObservationAbout = typeof observationAbout.$inferInsert;
export type Digest = typeof digests.$inferSelect;
export type NewDigest = typeof digests.$inferInsert;
