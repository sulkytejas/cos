# Atlas

A personal life assistant organized around **Chapters** — meaningful life arcs
with a start, a purpose, and an end.

```
pnpm install
pnpm dev
```

Open <http://localhost:3000>.

The first `pnpm dev` runs migrations and seeds the database with realistic data
(Varanasi trip, Ireland MBA move, Stratyfix seed round, Health baseline) before
Next.js starts. Delete `data/atlas.db` to start fresh.

## Stack

- Next.js 15 (App Router) · TypeScript · React 19
- Tailwind CSS v4 (config-in-CSS via `@theme`)
- Drizzle ORM + better-sqlite3 (local file at `./data/atlas.db`)
- tRPC v11 + TanStack Query
- Zod for input validation
- date-fns · lucide-react

No Postgres, no Docker, no auth, no deploy. The `data/` folder is gitignored.

## Project layout

```
src/
  app/                       Next App Router routes
    page.tsx                 Today
    chapters/                Chapters list
    chapter/[id]/            Chapter detail (Todos/Decisions/Journal/Links tabs)
    settings/                Connectors (placeholder) + data info
    api/trpc/[trpc]/         tRPC fetch adapter
    layout.tsx · providers.tsx · globals.css
  components/                Nav, Capture (⌘K), ChapterCard, TypeIcon, modals
    chapter/                 ChapterHeader + four tab components
  db/
    schema.ts                Drizzle schema (chapters, todos, decisions, entries, chapter_links)
    client.ts                Singleton better-sqlite3 + drizzle
    migrate.ts               Runs migrations + seedIfEmpty (used by `predev`)
    seed.ts                  Realistic seed data
  server/
    trpc.ts                  initTRPC + superjson
    routers/                 chapter, todo, decision, entry routers + _app root
  lib/
    trpc.ts                  React tRPC client
    utils.ts                 cn, date formatting, due-soon helpers
drizzle/                     Generated SQL migrations
data/                        SQLite file (gitignored)
```

## Scripts

| Command | What it does |
| --- | --- |
| `pnpm dev` | Migrate + seed if empty, then start Next dev server on :3000 |
| `pnpm build` | Production build |
| `pnpm typecheck` | `tsc --noEmit` |
| `pnpm db:generate` | Generate a new migration from `src/db/schema.ts` |
| `pnpm db:studio` | Open Drizzle Studio against `./data/atlas.db` |
| `pnpm db:seed` | Re-run seed (no-op if data already exists) |

## Design

Editorial, calm. Off-white paper (`#FAF7F2`) over warm hairline borders.
Instrument Serif for titles and big numbers, Manrope for body, JetBrains Mono
for dates and metadata. One accent (moss green, `#2D4A3A`) for primary actions
and one alert (ember, `#C2410C`) for due-soon items. No drop shadows.

## Capture

Press **⌘K** anywhere to open Capture — one textarea, save as todo / decision /
journal entry under any chapter. On mobile, the floating "+" button bottom-right
opens the same surface.
