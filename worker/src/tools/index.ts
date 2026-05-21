/**
 * Atlas's toolset. Each tool is a JSONSchema-typed function the agent can
 * call. Handlers read from the SQLite database (signals, chapters, briefs)
 * or stub external services.
 *
 * Add a tool by: define schema below, add a handler, register in TOOLS map.
 */
import { db, schema } from "../db";
import { and, desc, eq, gte, like } from "drizzle-orm";

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
      "Find what we know about a person across all signals — emails from them, calendar events with them, journal entries mentioning them.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Name or email to look up" },
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

  let rows;
  if (chapterId) {
    rows = db.select().from(schema.chapters).where(eq(schema.chapters.id, chapterId)).all();
  } else if (status) {
    rows = db.select().from(schema.chapters).where(eq(schema.chapters.status, status)).all();
  } else {
    rows = db.select().from(schema.chapters).all();
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
      result.todos = db.select().from(schema.todos).where(eq(schema.todos.chapterId, c.id)).all();
    }
    if (withDecisions) {
      result.decisions = db
        .select()
        .from(schema.decisions)
        .where(eq(schema.decisions.chapterId, c.id))
        .all();
    }
    if (withEntries) {
      result.entries = db
        .select()
        .from(schema.entries)
        .where(eq(schema.entries.chapterId, c.id))
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
    .where(eq(schema.signals.source, "gmail"))
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
    .where(eq(schema.signals.source, "calendar"))
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
    .where(eq(schema.briefs.chapterId, chapterId))
    .orderBy(desc(schema.briefs.createdAt))
    .limit(limit)
    .all();
}

function handlePersonLookup(args: ToolArgs) {
  const q = ((args.query as string) || "").toLowerCase();
  const allSignals = db.select().from(schema.signals).all();
  const matches = allSignals.filter((s) => {
    const raw = s.rawData as Record<string, unknown>;
    const text = JSON.stringify(raw).toLowerCase();
    return text.includes(q);
  });
  const allEntries = db.select().from(schema.entries).all();
  const entryHits = allEntries.filter((e) => e.content.toLowerCase().includes(q));

  return {
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
      sourceType: "internal",
      nextCheck: next,
      cadenceMinutes: 60 * 24,
      cadenceLabel: "daily",
      status: "active",
    })
    .run();
  return { ok: true, watcher_id: id };
}
