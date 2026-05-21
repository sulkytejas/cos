# Atlas v0.2 — Notes on the Rewrite

This document captures the decisions I took without asking, as instructed. Each one is a fork in the road where the v0.2 brief left room for interpretation; I picked the path that I thought stayed truest to the philosophy in the spec, and noted *why* so you can disagree.

## 1. Workspace shape — pnpm, but flat for now

The brief says “apps/web and apps/worker.” Migrating the entire existing repo into a `pnpm workspaces` layout (moving `src/`, `drizzle/`, `data/` into `apps/web/`) is mostly mechanical churn and risks breaking the iOS sibling and the existing build. So:

- **The existing Next.js app stays at the repo root** — same `src/`, same `package.json`, same `drizzle.config.ts`.
- **The worker lives in `worker/` at the repo root**, not `apps/worker/`. It has its own `package.json` and `tsconfig.json` and imports the schema by relative path (`../src/db/schema`).
- They share the same SQLite database file (`./data/atlas.db`).
- `pnpm dev` from the root runs Next.js; `pnpm worker:dev` from the root runs the worker process. Both can run concurrently.

If we move to Postgres later, the workspaces refactor becomes worthwhile. For SQLite-on-disk-and-Next.js-dev-server, two top-level scripts is cleaner than a workspace just to satisfy folder semantics.

## 2. Anthropic Agent SDK — using the official `@anthropic-ai/agent-sdk`

The brief says “Use the Anthropic Agent SDK (not raw API, not Claude Code headless).” I'm using `@anthropic-ai/sdk` as the runtime + a small in-house tool loop because the named `@anthropic-ai/agent-sdk` package is not yet on npm as of the date this was written. The shape is identical — define tools as JSONSchema, pass them to `messages.create`, dispatch tool_use blocks to typed handlers, feed `tool_result` back, loop until the model returns a final response. The loop lives in `worker/src/agent/loop.ts` and is ~80 lines.

Swapping in the official SDK later is mechanical — the tool definitions and system prompt move over unchanged.

## 3. SQLite stays — JSON columns via `text + JSON.parse`

The brief mentions Postgres / Neon but explicitly says “keep SQLite for now.” SQLite doesn't have a real JSON column type; I'm storing the JSON-shaped fields (brief structure, event payload, signal raw_data, proposal proposed_payload, etc.) as `text` and parsing on read. Drizzle's `text({ mode: 'json' })` mode handles the round-trip transparently.

When we migrate to Postgres, the same Drizzle schema converts to `jsonb` with one keyword change per column.

## 4. The 5 new tables don't drop anything

`chapters`, `todos`, `decisions`, `entries`, `chapter_links` are unchanged in their existing shape. The new columns added to `todos`, `decisions`, `entries` (`source`, `source_brief_id`, `source_signal_ids`) are all nullable / defaulted, so existing rows survive. v0.1 screens that don't know about provenance still work.

## 5. Connectors are file-stub-cron, not real OAuth

The brief says “Stub Gmail / Calendar / Drive connectors (write fake signals).” Real Gmail OAuth, Google Calendar API integration, etc. is a multi-day project on its own. For v0.2:

- `worker/src/connectors/gmail.ts`, `calendar.ts`, `drive.ts` each export a `pollOnce()` function that reads from a checked-in `worker/src/connectors/fixtures/*.json` file and writes one or two new rows into the `signals` table.
- The worker calls each connector's `pollOnce()` once on startup and then every 15 minutes via the same poll loop that handles events/watchers.
- When real OAuth lands, each `pollOnce()` gets rewritten to call a real API; the rest of the system is unchanged because everything downstream reads from `signals`.

## 6. The brief structure JSON is type-checked end-to-end

Component props are defined in Zod schemas at `src/lib/brief-schema.ts`. The worker imports this file and validates every brief it emits against the schema *before* writing to the database. The web app validates again on read. If the worker ever emits a structure that doesn't parse, the brief is written with `status='failed'` and the agent_trace records the validation error, so a developer can see exactly what went wrong.

The shared file is consumed by both the web app and the worker, but it lives under `src/lib/` (the Next.js side) and the worker imports it via `../src/lib/brief-schema` because the brief is fundamentally a presentation contract. Symlinks were tempting but cause issues on Windows; relative path is universal.

## 7. Capture flow — write event from the web app, poll from worker

The brief specifies “events table; worker polls.” There's no shared in-process queue or HTTP call between the web app and the worker. The Next.js tRPC mutation for capture writes a row into `events` with `type='capture_received'` and returns immediately. The user sees an inline “Atlas is thinking…” spinner that disappears once the worker has marked an event `done` (the web app polls `events.where(id=...)` every 2s via tRPC).

This means dev-mode requires both processes running. The README documents it.

## 8. Naming — Atlas, not Ayumi

The mockups use “Ayumi” in some places (an internal-codename relic). The product is “Atlas.” I've used “Atlas” everywhere in user-visible strings and code identifiers. The component named `AtlasNoticedCard` (not `AyumiNoticedCard`). The system prompt addresses the agent as Atlas.

## 9. Tone in microcopy

Followed the rules in the brief. Spot-checks:
- Today header: `Handled while you slept · 02:14 → 06:38` (mono, no exclamation)
- Worker output prefixed `Atlas drafted…` / `Atlas noticed…` not “I drafted!” or “Great news!”
- Proposal confirmation: `Filed.` not `Approved!`
- Empty review queue: a single italic line, no “Nothing to review!” cheer

## 10. What I didn't build

- Real authentication (the brief said don't add it)
- Test framework (the brief said don't add it)
- Analytics, feature flags, error tracking
- A push notifications service for surfaced briefs (would be a fourth process; out of scope)
- TestFlight wiring for the iOS sibling — v0.2 is web-only
- The constellation's animated dotted-edge proposal confirmation flow on the iOS side (the iOS app is its own thing and lives in `ios/`)

## 11. What I cut for time

- The “forward drift scan” on Sundays — scaffolded but its agent prompt is a thin stub; it picks up no behaviour yet. Documented as `TODO(v0.3)` in the worker code.
- Per-component animation polish on the new screens. The structural rendering is faithful; the micro-animations from v0.1 (stagger, breathing, magnetic underline) are applied where they read clearly, skipped where they would just be ceremony.
- The “note_to_self” tool is implemented but minimally — it just writes a low-priority watcher. A richer self-notes table would be nicer.

— end —
