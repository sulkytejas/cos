# Atlas

A personal life assistant organized around **Chapters** — meaningful life arcs with a start, a purpose, and an end. From v0.2 onward, Atlas is *agentic*: a background worker prepares Briefs from passive signals (Gmail, Calendar, Drive, voice) and writes proposals you approve, edit, or dismiss in a Review Queue. You type only what Atlas couldn't know.

```bash
pnpm install
pnpm dev           # runs migrations + seeds the SQLite DB, then Next.js on :3000
pnpm worker:dev    # in a second terminal — the agentic worker
```

Set `ANTHROPIC_API_KEY` in a root `.env` file to enable real preparation. Without it, the worker runs in a deterministic stub mode so the pipeline still works end-to-end in dev.

## v0.2 architecture

```
┌─────────────────────────┐         ┌────────────────────────┐
│ Atlas web (Next.js)     │         │ Atlas worker (Node)    │
│ - Reads/writes SQLite   │         │ - Polls events table   │
│ - User actions emit     │         │ - Runs agentic loops   │
│   events                │         │ - Writes briefs        │
│ - Renders briefs        │         │ - Manages watchers     │
│   from JSON structure   │         │ - Daily/forward scans  │
└──────────┬──────────────┘         └──────────┬─────────────┘
           │                                   │
           └─────────────┬─────────────────────┘
                         │
              ┌──────────▼───────────┐
              │ SQLite (./data)       │
              │ - chapters / todos /  │
              │   decisions / entries │
              │ - briefs (NEW)        │
              │ - events (NEW)        │
              │ - watchers (NEW)      │
              │ - signals (NEW)       │
              │ - proposals (NEW)     │
              └──────────┬───────────┘
                         │
              ┌──────────▼───────────┐
              │ Connectors (stubs)   │
              │ - Gmail              │
              │ - Calendar           │
              │ - Drive              │
              │ poll fixtures,       │
              │ write signals.       │
              └──────────────────────┘
```

The web app never calls the worker directly. They communicate through `events` (web writes, worker polls) and the canonical tables. Loose coupling all the way down.

**Why two processes:** the Next.js dev server reloads on file edits and would constantly interrupt long-running agent calls. Splitting them lets the worker run a steady event loop independent of code-reloads.

## Stack

- **Web**: Next.js 15 (App Router) · TypeScript · React 19 · Tailwind v4 · tRPC v11 · TanStack Query
- **Worker**: Node 20 · TypeScript · `@anthropic-ai/sdk` (the official client) wrapping a small custom tool-loop in `worker/src/agent/loop.ts`
- **Shared**: Drizzle ORM + better-sqlite3 (local file at `./data/atlas.db`), Zod for the BriefStructure contract
- **Fonts**: Instrument Serif (italic titles), Manrope (body), JetBrains Mono (dates / metadata). Bundled in the iOS sibling; loaded via Google Fonts here.

No Postgres, no Docker, no auth, no deploy. The `data/` folder is gitignored.

## Project layout

```
src/                              # Web app (Next.js)
  app/                            App Router routes
    page.tsx                      Today (briefs · handled overnight · watchers · todos)
    brief/[id]/                   Brief detail (renders via BriefRenderer)
    review/                       Review Queue (asked proposals + filed log)
    capture/                      Full-page agentic capture
    chapters/                     Chapters list
    chapter/[id]/                 Chapter detail (with provenance in tabs)
    settings/ · api/trpc/         (unchanged from v0.1)
  components/
    brief/                        v0.2 brief library: 10 sections + BriefRenderer + teasers
    chapter/                      Tabs (now provenance-aware)
    Nav.tsx · CaptureModal.tsx    Nav (now with Review item) · ⌘K capture
  db/
    schema.ts                     v0.1 tables + 5 new tables + provenance columns
    seed.ts · seed-v2.ts          Initial seed + v0.2 briefs/proposals/watchers
    client.ts · migrate.ts        Singleton SQLite handle + migrate-then-seed
  lib/
    brief-schema.ts               Zod schemas shared with the worker
  server/
    routers/                      tRPC routers: brief, proposal, event, watcher, signal added in v0.2

worker/                           Agentic worker (separate process)
  src/
    index.ts                      Long-running poll loop
    once.ts                       One-shot drain (for smoke tests)
    db.ts                         Opens its own handle to the same SQLite file
    agent/
      loop.ts                     The agent tool-loop (~80 lines)
      system-prompt.md            Atlas's worldview + the 8 principles + examples
    tools/index.ts                8 tools the agent can call
    processors/event.ts           Dispatch per event-type
    persist.ts                    Writes brief + proposals + watchers back
    connectors/                   Stubbed Gmail/Calendar/Drive + fixtures
  package.json · tsconfig.json

drizzle/                          Generated SQL migrations
data/                             SQLite file (gitignored)
```

## Scripts

| Command | What it does |
| --- | --- |
| `pnpm dev` | Migrate + seed if empty, then start Next dev server on :3000 |
| `pnpm worker:dev` | Start the agentic worker with file-watch reload |
| `pnpm worker:once` | Drain pending events once and exit (useful for smoke tests) |
| `pnpm worker:build` | Type-check the worker (`tsc --noEmit`) |
| `pnpm build` | Production build (web) |
| `pnpm typecheck` | `tsc --noEmit` (web) |
| `pnpm db:generate` | Generate a new migration from `src/db/schema.ts` |
| `pnpm db:studio` | Open Drizzle Studio against `./data/atlas.db` |
| `pnpm db:seed` | Re-run v0.1 seed (no-op if data already exists) |

## How Atlas thinks

The system prompt at `worker/src/agent/system-prompt.md` is the source of truth for Atlas's worldview and the contract on the JSON shape it must emit. The 8 principles in that file shape every architectural decision in this repo — read it first if you're trying to extend the agent.

Briefs are composed from a fixed library of 10 sections (`PersonCard`, `TimelineSection`, `PredictionBlock`, `MaterialsChecklist`, `OptionList`, `TacticalNote`, `QuoteCard`, `WatcherCard`, `DiffBlock`, `ActionStrip`). Atlas can only compose; it cannot invent new components. If it tries, the `BriefRenderer` falls back to a plain-text section and logs the unknown component name to `dev_unknown_components` for follow-up.

## Tone

Every string in the app is intentional. Atlas never exclaims, never performs ("Great job!"). It refers to itself sparingly ("Atlas noticed", "I drafted"). Numbers and dates render in mono. Emphasis is serif italic, never bold. Microcopy in the worker's outputs follows the same rules; see the "Tone for the strings you write" section in the system prompt.

## What's not done

See `NEW_IN_V2.md` for design decisions taken without asking, including features explicitly cut from scope (web Constellation page, forward-drift scan, real OAuth connectors, animations on the new screens).
