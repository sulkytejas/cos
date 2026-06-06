/**
 * Atlas's toolset. Each tool is a JSONSchema-typed function the agent can
 * call. Handlers read from the SQLite database (signals, chapters, briefs)
 * or stub external services.
 *
 * Add a tool by: define schema below, add a handler, register in TOOLS map.
 */
import { db, schema } from "../db";
import { and, desc, eq, gte, inArray, isNull, like, ne } from "drizzle-orm";
import { findPerson } from "../memory/people";

// JSONSchema tool definitions — passed to the Anthropic API.
export const TOOL_SCHEMAS = [
  {
    name: "chapter_query",
    description:
      "Read chapters and their contents. Returns chapters with their todos, decisions, and recent journal entries. Use filters to narrow.",
    input_schema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: ["active", "upcoming", "paused", "done"],
          description: "Limit to chapters with this status",
        },
        chapter_id: { type: "string", description: "Look up a single chapter by id" },
        with_todos: { type: "boolean", default: false },
        with_decisions: { type: "boolean", default: false },
        with_entries: { type: "boolean", default: false },
      },
    },
  },
  {
    name: "gmail_search",
    description:
      "Search the user's email signals. Returns raw_data for matching emails. Use this for any 'what did Karan say' / 'did the studio email' type lookups.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Natural-language match against subject/body" },
        from: { type: "string", description: "Optional sender filter" },
        since: { type: "string", description: "ISO datetime; only return signals after this" },
      },
      required: ["query"],
    },
  },
  {
    name: "calendar_query",
    description:
      "Get calendar events from signals between start and end. Returns title, time, attendees if available.",
    input_schema: {
      type: "object",
      properties: {
        start: { type: "string", description: "ISO datetime start of range" },
        end: { type: "string", description: "ISO datetime end of range" },
      },
      required: ["start", "end"],
    },
  },
  {
    name: "brief_history",
    description:
      "Read prior briefs Atlas has prepared for a chapter. Returns title, situation, drafted_at. Use to diff against what's changed.",
    input_schema: {
      type: "object",
      properties: {
        chapter_id: { type: "string" },
        limit: { type: "number", default: 5 },
      },
      required: ["chapter_id"],
    },
  },
  {
    name: "person_lookup",
    description:
      "Find what we know about a person. Returns their contact card (canonical name, every known address/nickname, role/org) and the living notes kept about them — each note with receipts — then the raw signal/journal mentions.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Name or email to look up" },
      },
      required: ["query"],
    },
  },
  {
    name: "memory_lookup",
    description:
      "Check the notebook mid-thought — for the rare thing nobody pre-fetched. Ask by a person's name/email or free text; returns living notes with receipts. Set include_history to also see end-dated notes ('that was true until April').",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "A person (name or email) or free text to match against note bodies" },
        include_history: {
          type: "boolean",
          default: false,
          description: "Also return superseded/end-dated notes, marked with when they stopped being true",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "web_search",
    description:
      "Stubbed in v0.2: returns a 'no results' shape. Real web search lands in v0.3. The agent should not rely on this for grounding.",
    input_schema: {
      type: "object",
      properties: { query: { type: "string" } },
      required: ["query"],
    },
  },
  {
    name: "web_fetch",
    description: "Stubbed in v0.2 — same caveat as web_search.",
    input_schema: {
      type: "object",
      properties: { url: { type: "string" } },
      required: ["url"],
    },
  },
  {
    name: "note_to_self",
    description:
      "Leave yourself a low-priority watcher that will surface in N hours. Use for things that aren't urgent enough to be a brief but worth not forgetting.",
    input_schema: {
      type: "object",
      properties: {
        text: { type: "string" },
        in_hours: { type: "number", default: 24 },
        chapter_id: { type: "string" },
      },
      required: ["text"],
    },
  },
] as const;

// ─── handlers ───────────────────────────────────────────────────────

type ToolArgs = Record<string, unknown>;

export async function handleTool(name: string, args: ToolArgs): Promise<unknown> {
  switch (name) {
    case "chapter_query":
      return handleChapterQuery(args);
    case "gmail_search":
      return handleGmailSearch(args);
    case "calendar_query":
      return handleCalendarQuery(args);
    case "brief_history":
      return handleBriefHistory(args);
    case "person_lookup":
      return handlePersonLookup(args);
    case "memory_lookup":
      return handleMemoryLookup(args);
    case "web_search":
      return { results: [], note: "web_search is stubbed in v0.2" };
    case "web_fetch":
      return { ok: false, body: "", note: "web_fetch is stubbed in v0.2" };
    case "note_to_self":
      return handleNoteToSelf(args);
    default:
      return { error: `unknown tool: ${name}` };
  }
}

function handleChapterQuery(args: ToolArgs) {
  const status = args.status as schema.ChapterStatus | undefined;
  const chapterId = args.chapter_id as string | undefined;
  const withTodos = !!args.with_todos;
  const withDecisions = !!args.with_decisions;
  const withEntries = !!args.with_entries;

  // §4.d: never let the agent see tombstoned rows.
  let rows;
  if (chapterId) {
    rows = db
      .select()
      .from(schema.chapters)
      .where(and(eq(schema.chapters.id, chapterId), isNull(schema.chapters.deletedAt)))
      .all();
  } else if (status) {
    rows = db
      .select()
      .from(schema.chapters)
      .where(and(eq(schema.chapters.status, status), isNull(schema.chapters.deletedAt)))
      .all();
  } else {
    rows = db.select().from(schema.chapters).where(isNull(schema.chapters.deletedAt)).all();
  }

  return rows.map((c) => {
    const result: Record<string, unknown> = {
      id: c.id,
      title: c.title,
      type: c.type,
      status: c.status,
      startDate: c.startDate,
      endDate: c.endDate,
      purpose: c.purpose,
    };
    if (withTodos) {
      result.todos = db
        .select()
        .from(schema.todos)
        .where(and(eq(schema.todos.chapterId, c.id), isNull(schema.todos.deletedAt)))
        .all();
    }
    if (withDecisions) {
      result.decisions = db
        .select()
        .from(schema.decisions)
        .where(and(eq(schema.decisions.chapterId, c.id), isNull(schema.decisions.deletedAt)))
        .all();
    }
    if (withEntries) {
      result.entries = db
        .select()
        .from(schema.entries)
        .where(and(eq(schema.entries.chapterId, c.id), isNull(schema.entries.deletedAt)))
        .orderBy(desc(schema.entries.date))
        .limit(10)
        .all();
    }
    return result;
  });
}

function handleGmailSearch(args: ToolArgs) {
  const query = ((args.query as string) || "").toLowerCase();
  const from = (args.from as string | undefined)?.toLowerCase();
  const since = args.since as string | undefined;

  let rows = db
    .select()
    .from(schema.signals)
    .where(and(eq(schema.signals.source, "gmail"), isNull(schema.signals.deletedAt)))
    .orderBy(desc(schema.signals.arrivedAt))
    .all();

  if (since) rows = rows.filter((r) => r.arrivedAt >= since);

  const matches = rows.filter((r) => {
    const raw = r.rawData as Record<string, unknown>;
    const subject = String(raw.subject ?? "").toLowerCase();
    const body = String(raw.body ?? "").toLowerCase();
    const senderEmail = String(raw.from ?? "").toLowerCase();
    if (from && !senderEmail.includes(from)) return false;
    if (!query) return true;
    return subject.includes(query) || body.includes(query) || senderEmail.includes(query);
  });

  return matches.slice(0, 10).map((r) => ({
    id: r.id,
    arrivedAt: r.arrivedAt,
    summary: r.summary,
    ...(r.rawData as Record<string, unknown>),
  }));
}

function handleCalendarQuery(args: ToolArgs) {
  const start = (args.start as string) || new Date().toISOString();
  const end = (args.end as string) || new Date(Date.now() + 7 * 86400_000).toISOString();
  const rows = db
    .select()
    .from(schema.signals)
    .where(and(eq(schema.signals.source, "calendar"), isNull(schema.signals.deletedAt)))
    .all();
  const matches = rows.filter((r) => {
    const raw = r.rawData as Record<string, unknown>;
    const startsAt = String(raw.startsAt ?? r.arrivedAt);
    return startsAt >= start && startsAt <= end;
  });
  return matches.map((r) => ({
    id: r.id,
    ...(r.rawData as Record<string, unknown>),
  }));
}

function handleBriefHistory(args: ToolArgs) {
  const chapterId = args.chapter_id as string;
  const limit = (args.limit as number | undefined) ?? 5;
  return db
    .select({
      id: schema.briefs.id,
      title: schema.briefs.title,
      situation: schema.briefs.situationDescription,
      createdAt: schema.briefs.createdAt,
    })
    .from(schema.briefs)
    .where(and(eq(schema.briefs.chapterId, chapterId), isNull(schema.briefs.deletedAt)))
    .orderBy(desc(schema.briefs.createdAt))
    .limit(limit)
    .all();
}

function handlePersonLookup(args: ToolArgs) {
  const q = ((args.query as string) || "").toLowerCase();

  // Memory layer Phase 1.3: same tool name, richer answer — the contact card
  // and Ayumi's notes lead, the raw signal/journal mentions follow as before.
  // Tools run single-tenant (see runAgent), so the bootstrap owner scopes reads.
  const card = findPerson(schema.BOOTSTRAP_USER_ID, (args.query as string) || "");
  let contact_card: Record<string, unknown> | null = null;
  let notes: Record<string, unknown>[] = [];
  if (card) {
    contact_card = {
      id: card.id,
      name: card.canonicalName,
      handles: card.handles,
      role: card.role,
      org: card.org,
      firstSeenAt: card.firstSeenAt,
      lastSeenAt: card.lastSeenAt,
    };
    // Living notes about any of the card's handles: not struck, not end-dated.
    const handles = (card.handles ?? []).map((h) => h.toLowerCase());
    if (handles.length > 0) {
      const aboutRows = db
        .select({ observationId: schema.observationAbout.observationId })
        .from(schema.observationAbout)
        .where(inArray(schema.observationAbout.handle, handles))
        .all();
      const ids = [...new Set(aboutRows.map((r) => r.observationId))];
      if (ids.length > 0) {
        notes = db
          .select()
          .from(schema.observations)
          .where(
            and(
              inArray(schema.observations.id, ids),
              ne(schema.observations.kind, "prediction"),
              isNull(schema.observations.deletedAt),
              isNull(schema.observations.invalidatedAt),
              isNull(schema.observations.struckAt),
            ),
          )
          .orderBy(desc(schema.observations.weight), desc(schema.observations.lastSeenAt))
          .limit(20)
          .all()
          .map((o) => ({
            body: o.body,
            kind: o.kind,
            confidence: o.confidence,
            timesConfirmed: o.weight,
            lastSeenAt: o.lastSeenAt,
            receipts: o.receipts,
          }));
      }
    }
  }

  const allSignals = db.select().from(schema.signals).where(isNull(schema.signals.deletedAt)).all();
  // Search raw signals by the query AND by every known handle, so "Karan"
  // also finds mail from karan@sequoiacap.com.
  const needles = [...new Set([q, ...((card?.handles ?? []).map((h) => h.toLowerCase()))])].filter(Boolean);
  const matches = allSignals.filter((s) => {
    const text = JSON.stringify(s.rawData).toLowerCase();
    return needles.some((n) => text.includes(n));
  });
  const allEntries = db.select().from(schema.entries).where(isNull(schema.entries.deletedAt)).all();
  const entryHits = allEntries.filter((e) => {
    const text = e.content.toLowerCase();
    return needles.some((n) => text.includes(n));
  });

  return {
    contact_card,
    notes,
    signal_mentions: matches.slice(0, 10).map((s) => ({
      source: s.source,
      arrivedAt: s.arrivedAt,
      summary: s.summary,
    })),
    journal_mentions: entryHits.slice(0, 5).map((e) => ({
      date: e.date,
      content: e.content,
      chapterId: e.chapterId,
    })),
  };
}

/**
 * memory_lookup — memory layer Phase 4.2 (R3): the mid-thought dig nobody
 * pre-fetched. Person queries resolve via the contact card's handles; free
 * text matches note bodies. Living notes by default; `include_history` adds
 * end-dated ones marked "true until <date>". Predictions never surface here.
 */
function handleMemoryLookup(args: ToolArgs) {
  const query = ((args.query as string) || "").trim();
  const includeHistory = !!args.include_history;
  if (!query) return { notes: [], history: [] };
  const userId = schema.BOOTSTRAP_USER_ID;

  // Person path: card → handles → about-rows → note ids.
  const card = findPerson(userId, query);
  let ids: string[] = [];
  if (card) {
    const handles = (card.handles ?? []).map((h) => h.toLowerCase());
    if (handles.length > 0) {
      ids = [
        ...new Set(
          db
            .select({ observationId: schema.observationAbout.observationId })
            .from(schema.observationAbout)
            .where(
              and(
                eq(schema.observationAbout.userId, userId),
                inArray(schema.observationAbout.handle, handles),
              ),
            )
            .all()
            .map((r) => r.observationId),
        ),
      ];
    }
  }

  let rows = ids.length
    ? db
        .select()
        .from(schema.observations)
        .where(
          and(
            inArray(schema.observations.id, ids),
            ne(schema.observations.kind, "prediction"),
            isNull(schema.observations.deletedAt),
          ),
        )
        .all()
    : [];

  // Free-text fallback (or supplement when the card path found nothing).
  if (rows.length === 0) {
    const q = query.toLowerCase();
    rows = db
      .select()
      .from(schema.observations)
      .where(
        and(
          eq(schema.observations.userId, userId),
          ne(schema.observations.kind, "prediction"),
          isNull(schema.observations.deletedAt),
        ),
      )
      .all()
      .filter((o) => o.body.toLowerCase().includes(q));
  }

  const living = rows
    .filter((o) => !o.invalidatedAt && !o.struckAt)
    .sort((a, b) => b.weight - a.weight || b.lastSeenAt.localeCompare(a.lastSeenAt))
    .slice(0, 20);
  const history = includeHistory
    ? rows
        .filter((o) => o.invalidatedAt && !o.struckAt)
        .sort((a, b) => (b.invalidatedAt ?? "").localeCompare(a.invalidatedAt ?? ""))
        .slice(0, 10)
    : [];

  return {
    person: card ? { name: card.canonicalName, handles: card.handles } : null,
    notes: living.map((o) => ({
      id: o.id,
      body: o.body,
      kind: o.kind,
      timesConfirmed: o.weight,
      lastSeenAt: o.lastSeenAt,
      receipts: o.receipts,
    })),
    history: history.map((o) => ({
      body: o.body,
      trueUntil: o.invalidatedAt,
      receipts: o.receipts,
    })),
  };
}

function handleNoteToSelf(args: ToolArgs) {
  const text = args.text as string;
  const inHours = (args.in_hours as number | undefined) ?? 24;
  const chapterId = args.chapter_id as string | undefined;
  const id = `note-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const next = new Date(Date.now() + inHours * 60 * 60 * 1000).toISOString();
  db.insert(schema.watchers)
    .values({
      id,
      chapterId: chapterId ?? null,
      description: text,
      prompt: `Re-examine: ${text}`,
      updatedAt: new Date().toISOString(),
      sourceType: "internal",
      nextCheck: next,
      cadenceMinutes: 60 * 24,
      cadenceLabel: "daily",
      status: "active",
    })
    .run();
  return { ok: true, watcher_id: id };
}
