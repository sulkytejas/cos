# Ayumi — Server Architecture & Cut-Over Design

> Moving the "brain" off the iOS device and back onto a single always-on server, behind one throttled AI gateway, without a big-bang rewrite.

---

## 1. TL;DR

- **Move the brain to the server, keep the iOS UI.** The on-device agent loop, all Anthropic calls, the connectors, and overnight work move to a single always-on Oracle Free-Tier VM running the existing Next.js API + the existing worker over the existing SQLite file. iOS becomes a thin client that submits intents and reads results; its SwiftData store stays as an offline read-mirror so the `@Query`-driven screens keep working.
- **One AI gateway is the hard ceiling — built first.** A single `src/server/anthropic/gateway.ts` becomes the *only* holder of `ANTHROPIC_API_KEY` and the *only* path to `messages.create`. It enforces a triple token-bucket (RPM / uncached-ITPM / OTPM), a global concurrency cap, `Retry-After` honoring, a per-user/day budget persisted in SQLite, and prompt-cache reuse. This is what stops the 24/7 re-breach of the org Sonnet limit.
- **Default to Tier-1 bucket sizes and self-correct from response headers.** The org tier is unconfirmed; "it breached" is *not* evidence of Tier 2. We ship conservative (Tier-1) caps and clamp every bucket to `min(configured, server-reported-limit)` read off `anthropic-ratelimit-*` headers on every response. Over-throttling is recoverable; breaching is not. Models pinned in one place: **`claude-sonnet-4-6`** for the agent, **`claude-haiku-4-5`** for one-shot Ask.
- **Reuse, don't rewrite.** The worker's event loop, `processors/event.ts`, `agent/loop.ts`, `tools/index.ts`, `persist.ts`, and the 10 tRPC routers are kept verbatim behind the gateway. iOS points at the existing `event.emit` / `event.status` / `brief.forToday` / `proposal.*` contract — the same submit→poll→read flow the screens already run locally.
- **Incremental, gated cut-over.** Phase 0 lands the gateway server-side with **zero** iOS change and immediately stops the breach. Auth + key-removal is the gating prerequisite for pointing the keyless client at a public URL (never a fail-open default user). Multi-device delta-sync, soft-deletes, and APNs are **deferred** to later phases — they are not required for the security win.

---

## 2. Why a Server (the four drivers, tied to Ayumi's premise)

Ayumi's premise is a personal chief-of-staff that *quietly drafts while you sleep, watches the things you care about, and surfaces a brief when it matters.* That premise is structurally incompatible with an on-device-only brain, for four concrete reasons:

1. **API-key security (non-negotiable).** Today every device ships `ANTHROPIC_API_KEY` in `UserDefaults["AnthropicAPIKey"]` and calls `api.anthropic.com` directly (`ClaudeClient.swift`). A key in a plaintext plist cannot ship to users — it is extractable from any device/backup and one leaked key trashes the entire org's rate limit. The key must live in exactly one place: a server env file. This driver alone forces a server.

2. **Overnight / continuous work.** iOS suspends backgrounded apps; `BGAppRefreshTask` is best-effort (~30 min, no guarantee) and cannot run a multi-turn agent overnight. "Drafted while you slept" requires a process that is *actually awake* at 3am — i.e. an always-on server, not a phone.

3. **Central rate-limit control.** There are three uncoordinated Anthropic integrations today (worker, `/api/ask`, iOS), none sharing a throttle. The worker's `while(true)` 30s loop calling Sonnet with **no** throttle is exactly what breached the org Sonnet limit **38× in 24h**. The only way a token bucket can bound org-wide usage is a single server-side choke point every call passes through.

4. **Connectors + multi-device sync.** Real Gmail/Drive/Calendar connectors need long-lived OAuth tokens and a 24/7 poller — neither belongs on a phone. (EventKit calendar is the one exception: it is device-only and will *push* signals up.) Multiple devices need one source of truth.

The server is not an optimization; it is the only architecture in which Ayumi's core promise is deliverable and shippable.

---

## 3. Current State — Two Parallel Implementations

Two complete implementations of the same system exist. The v0.6 iOS app re-implemented on-device what the v0.2 server already had server-side. The cut-over keeps the server's data + agent code and the iOS UI, and deletes the on-device brain.

| Area | v0.2 Server (`src/`, `worker/`) | v0.6 iOS (`ios/Atlas/`) | Cut-over verdict |
|---|---|---|---|
| **DB schema** | `src/db/schema.ts` — 11 tables, full enums/relations | 10 SwiftData `@Model` classes mirroring it | **Reuse server schema as source of truth**; SwiftData becomes a read-mirror |
| **DB client** | `src/db/client.ts` — better-sqlite3 WAL | on-device SQLite | **Reuse** as-is on the VM (the reason SQLite is viable) |
| **tRPC routers** | 10 routers (chapter/todo/decision/entry/brief/proposal/event/watcher/signal/morning) | n/a (screens hit SwiftData) | **Reuse** read+decision surface; add generation behind gateway |
| **Agent loop** | `worker/src/agent/loop.ts` — Sonnet, 12 turns, **no throttle** | `AtlasAgent.swift` foreground loop, `ClaudeClient.swift` direct | **Reuse worker loop behind gateway; delete iOS loop** |
| **Tools** | `worker/src/tools/index.ts` — 7 read tools, parse-final-JSON persist | `AgentTools.swift` — 12 tools incl. write-tools | **Reuse worker tools + `persist.ts`**; keep the parse-final path |
| **Connectors** | `worker/src/connectors/*` — fixtures, 15-min poll | Swift fixtures + **real EventKit** | **Reuse worker connector skeleton**; iOS pushes EventKit signals |
| **Throttle** | none (the breach source) | per-device `LLMBudget`, fixed `[1,3,7]s` backoff, no `Retry-After` | **Build fresh** — the one greenfield must-have |
| **Auth / userId** | none — `createContext: () => ({})`, no `userId` column | ships the Anthropic key, authenticates to nothing | **Build fresh** — hashed bearer token + `userId` column |
| **Brief render contract** | `src/lib/brief-schema.ts` | `BriefStructure.swift` (byte-mirror) | **Keep both byte-compatible** — server emits, iOS renders unchanged |

**The reusable core is large.** The genuinely new work is: the gateway, an auth layer, soft-delete/sync (deferred), and real OAuth connectors (deferred). Everything else is rewiring existing code.

---

## 4. Target Architecture

### 4.0 Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│  iOS app (thin client) — ios/Atlas                                         │
│                                                                            │
│   6 SwiftUI screens ──@Query──▶ SwiftData (OFFLINE READ-MIRROR)            │
│        │                              ▲                                     │
│        │ submit intent                │ upsert on sync()                    │
│        ▼                              │                                     │
│   AtlasRepo (@Observable, sole SwiftData writer)                          │
│        │   • Keychain bearer token (NO Anthropic key)                       │
│        │   • EventKit → pushCalendarSignals()                              │
│        ▼                                                                    │
│   AtlasAPI (URLSession, HTTPS only, Retry-After aware)                     │
└────────┼───────────────────────────────────────────────────────────────────┘
         │  HTTPS  Authorization: Bearer <deviceToken>
         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Oracle Cloud Free-Tier ARM VM (always-on, $0)                            │
│                                                                            │
│   Caddy :443  ──auto-TLS──▶  Next.js :3000 (127.0.0.1 only)               │
│                                  │                                         │
│        ┌─────────────────────────┴───────────────┐                        │
│        │ tRPC routers (createContext → userId)    │                        │
│        │ event.emit / event.status / brief.* /    │                        │
│        │ proposal.* / chapter.* / ai.ask / sync   │                        │
│        └───────────────┬──────────────────────────┘                       │
│                        │                                                   │
│   worker (systemd, Restart=always)                                        │
│     claim queue → scheduler (daily/drift/watcher/connector)               │
│        │                                                                   │
│        ▼                                                                   │
│   ╔══════════════════════════════════════════════════╗                   │
│   ║  AI GATEWAY  src/server/anthropic/gateway.ts      ║                   │
│   ║  • ONLY holder of ANTHROPIC_API_KEY               ║                   │
│   ║  • ONLY caller of messages.create                 ║                   │
│   ║  • triple token-bucket (RPM/ITPM/OTPM)            ║──────▶  api.anthropic.com
│   ║  • global concurrency cap + Retry-After           ║         (Sonnet 4.6 / Haiku 4.5)
│   ║  • per-user/day budget (usageLedger in SQLite)    ║                   │
│   ║  • prompt-cache (system+tools, ttl 1h)            ║                   │
│   ╚══════════════════════════════════════════════════╝                   │
│                        │                                                   │
│   ┌────────────────────┴───────────┐   ┌───────────────────────────────┐ │
│   │ better-sqlite3 WAL              │   │ connectors (Gmail/Drive/Cal)  │ │
│   │ /opt/atlas/data/atlas.db        │◀──│  OAuth tokens (encrypted)     │ │
│   │ (shared by Next.js + worker)    │   │  + iOS-pushed EventKit signals│ │
│   └─────────────────────────────────┘   └───────────────────────────────┘ │
│                                                                            │
│   litestream / nightly .backup → OCI Object Storage (20 GB free)          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.a Client API Contract

**Decision: point Swift at the EXISTING tRPC endpoints over HTTP with a thin Codable envelope-unwrapper — do not build a parallel REST/v1 facade for v1.** The iOS screens already implement the exact submit→poll→read flow the tRPC bridge exposes; the only friction is superjson's `{json,meta}` wire shape, which is solved once with a ~30-line Swift unwrapper, not 14 shim route files. (A REST/v1 facade is revisited only if a second non-Swift client appears.)

The client speaks tRPC-over-HTTP from an `actor AtlasAPI`:
- **Queries** → `GET /api/trpc/<proc>?input=<encoded>`; **mutations** → `POST /api/trpc/<proc>` with `{json: payload}` body.
- Unwrap `result.data.json`. Hand-written `Codable` DTOs per endpoint keep enum raw values (`journal_entry`, `chapter_link`, `BriefStructure` kinds) under our control and byte-compatible with the server.
- Every request carries `Authorization: Bearer <deviceToken>` from the **Keychain**. On a `429`, read `Retry-After` and back off (the gateway owns the real throttle; the API forwards its 429).

**The endpoints the thin client uses (all existing, reused as-is):**

| Screen | Call | Procedure (existing) |
|---|---|---|
| Today | read surfaced briefs + overnight + watching | `brief.forToday`, `signal.overnight`, `watcher.active`, `proposal.countsForToday` |
| Brief | read one brief; wire Start/Snooze | `brief.byId`; **add** `brief.act({id, action})` → `brief.setStatus` + `event.emit({type:"brief_acted_on"})` |
| Capture | submit → poll → read proposals | `event.emit({type:"capture_received"})` → `event.status(id)` → proposals where `createdAt >= job.createdAt` |
| Chapters | constellation + detail | `chapter.list`, `chapter.get`, `watcher.active`, `brief.recentByChapter` |
| Review | approve / dismiss | `proposal.forReview`, `proposal.approve`, `proposal.dismiss` (server-side `writePayload` fan-out — replaces on-device `Proposal.materialize`) |
| Search | grounded RAG | **add** `ai.ask({query, scope?, history?})` → gateway one-shot (Haiku) with server-side grounding |

**Job contract for capture:** `event.emit` returns `{id}`; the client polls `event.status(id)` every 1s up to 90s (matching `CaptureScreen.swift`'s existing loop). On `done`, the status response also returns `resultProposalIds` so the screen renders exactly the proposals this capture produced — **do not** infer via `createdAt >= sendStart` once capture is async (a background scan can interleave proposals into that window).

**Hardening required before the keyless client points at a public URL:**
- `ai.ask` and any Anthropic-touching procedure **must** validate input with Zod (`message ≤ ~4k chars`, `history ≤ N turns`, `context` sliced) and **must** require a valid token. The current `/api/ask` raw-casts the body and lets unbounded `history` through — that becomes a public token-burn endpoint otherwise.
- `sync.*` (when it lands) is `protectedProcedure` from day one — it is the bulk-read endpoint.

### 4.b AI Gateway + Throttle (concrete numbers)

**One module, one choke point:** `src/server/anthropic/gateway.ts` owns the only `new Anthropic()` and the only `ANTHROPIC_API_KEY` read. Add an ESLint `no-restricted-imports` rule banning `@anthropic-ai/sdk` everywhere else. Every caller uses two functions:

- `createMessage(req: GatewayRequest, ctx): Promise<Message>` — throttled 1:1 wrapper around `messages.create`.
- `runAgentLoop(opts): Promise<AgentResult>` — the worker's tool-use loop moved **inside** the gateway, so **every** turn (up to `MAX_TURNS=12`) re-enters the buckets, not just the first call. (One `daily_scan` fans out to up to 12 sequential Sonnet calls — throttling only the entry doesn't bound that.)

Callers route by **intent** (`route: 'agent' | 'one_shot'`), never by model string — the gateway picks the model. This kills the model-skew (`worker sonnet-4-5` vs `iOS sonnet-4-6` vs `ask sonnet-4-5`).

**Triple token bucket (continuous refill, matching Anthropic's own model).** A request must acquire from all three before sending: 1 RPM token, an `estimateInputTokens()` ITPM reservation, and a `maxTokens` OTPM reservation. After the response, **reconcile** against `usage`:
- Charge ITPM only `input_tokens + cache_creation_input_tokens`. **`cache_read_input_tokens` is free** for ITPM (verified in live docs) — so cache hits cost zero ITPM, which is the whole point of caching the prefix.
- Refund the over-reservation or debit the excess.

**Starting config (`src/server/anthropic/config.ts`, env-overridable) — DEFAULT TO TIER 1, auto-raise from headers:**

| Route | Model | RPM | ITPM (uncached) | OTPM |
|---|---|---|---|---|
| `agent` | `claude-sonnet-4-6` | **42** | **25,500** | **6,800** |
| `one_shot` | `claude-haiku-4-5` | **42** | **42,500** | **8,500** |

These are 85% of the **Tier-1** limits (Sonnet 4.x Tier 1 = 50 RPM / 30K ITPM / 8K OTPM; Haiku 4.5 Tier 1 = 50 / 50K / 10K; Sonnet and Haiku are **separate pools**, so independent buckets). The gateway reads `anthropic-ratelimit-{requests,input-tokens,output-tokens}-limit` on **every** response and clamps each bucket to `min(configured, server-reported)`. If the org is actually Tier 2 (1000 / 450K / 90K), the buckets self-raise within a few requests. **If the org is Tier 1, the agent's ~215-line system prompt across a 12-turn loop is near-unviable WITHOUT the prompt cache** — so cache enforcement is a launch blocker, asserted at startup.

Other config: `maxConcurrency = 4` global, but **reserve 1 slot for `one_shot`/interactive** so an overnight burst can never fully starve a live Ask (3 background / 1 interactive). `perUserDailyTokenCap = 300_000`, **defined against `input + cache_creation + output` only** (excluding free cache reads — porting the iOS number but fixing its accounting). `retryMax=5`, `retryBaseMs=1000`, `retryCapMs=60000`, full jitter. `estimateInputTokens` = chars/3.5 over the **new turn only** when the prefix is cached (reserve the full prefix only on the first, cache-write turn) — otherwise a 12-turn loop over-reserves the cached prefix on every turn and self-throttles below the real ceiling.

**429 / 529 handling, branched:**
- `429` with `remaining≈0` (token exhaustion) → pause the **whole bucket** until the reset time; every queued acquire awaits it.
- `429` without (acceleration limit) → reduce admission rate gradually for a cooldown, don't hard-pause-then-full-resume (full resume re-triggers it).
- `529` (Overloaded) → per-request jittered exponential backoff; do **not** pause the shared bucket (it's not a rate decision).
- `401/403/400-credit` → trip a circuit breaker (ported from `AtlasLLM`) that fails fast for a cooldown — these won't fix themselves.

**Prompt caching (the single highest-leverage lever).** Port `ClaudeClient.swift`'s exact strategy into the gateway for both routes: `system` as a content block with `cache_control:{type:"ephemeral"}`; tools sorted by name with `cache_control` on the last tool decl for a byte-stable prefix; **`ttl:"1h"`** on the agent prefix (overnight scans have gaps >5 min, so a 5-min entry expires between events and re-pays the write premium). `prewarm()` (a `max_tokens:0` call on the agent prefix) runs at worker startup. The worker today sends `system` as a plain string with tools unsorted and **no** `cache_control` — re-billing the full ~215-line prefix as fresh ITPM on every one of up to 12 turns. That is the exact lever that trips the input limit; the gateway closes it.

**Cross-process correctness (ship-blocker fix).** The buckets are in-memory JS objects, but the gateway links into **both** the Next.js process and the worker process — two processes cannot share an in-memory bucket, so naively they'd each admit 85% and combined ~170% → re-breach. **Resolution: make Anthropic calls single-process.** `ai.ask` in Next.js **enqueues** a `one_shot` job that the worker drains; only the worker ever calls `messages.create`, so the in-memory bucket is authoritative. (This fits the queue model the worker already uses. The alternative — a SQLite `token_bucket` table with atomic `UPDATE…RETURNING` decrements shared by both processes — is the fallback if Next.js must call Anthropic inline.)

### 4.c Worker Runtime

Keep one long-running Node process (`worker/src`) but split its body into three modules; reuse `processors/event.ts`, `agent/loop.ts`, `persist.ts`, `connectors/*` verbatim.

- **`queue.ts` — atomic claim.** Replace single-row drain with `UPDATE events SET status='processing', claimedAt=now, attempts=attempts+1 WHERE id IN (SELECT id FROM events WHERE status='pending' ORDER BY createdAt LIMIT :batch) RETURNING *`, then run claimed events through a bounded pool. **Set `WORKER_CONCURRENCY=1` for writes** — SQLite is single-writer, so write-concurrency is illusory throughput; the gateway's *network* concurrency is what matters. The per-tick `cap=2` rate hack is deleted — rate-limiting now belongs to the gateway.
- **`scheduler.ts` — wall-clock timers, not `getHours()`.** `setTimeout` to the next 06:00 local for `daily_scan` (re-armed after each fire), Sundays for `forward_drift_scan`, a 60s sweep enqueuing `watcher_due` for due watchers, and a 15-min connector poll. Scans **enqueue** an event (they don't call the agent directly) with a `dedupeKey`. **Critical: on every wakeup and on boot, run a catch-up check** — "if no `daily_scan` with `dedupeKey=daily_scan:<today>` exists AND local time ≥ 06:00, enqueue it now." A bare `setTimeout` silently misses the window on VM suspend, NTP jump, or a post-06:00 restart — and the `dedupeKey` would then suppress the catch-up. The catch-up makes the scan exactly-once **and** guaranteed-to-eventually-fire. This is the headline overnight failure to avoid, and it must fail *open* (run late), not *closed* (skip silently).
- **`runtime.ts` — boot + graceful drain.** Boots the pool + scheduler; `SIGTERM` sets a draining flag, awaits in-flight runs up to `SHUTDOWN_GRACE_MS=20000`, closes SQLite, `exit(0)`. systemd `Restart=always`, `TimeoutStopSec=25`.

**Idempotency at the OUTPUT layer, not just the event layer (ship-blocker).** A unique `events.dedupeKey` dedupes event *rows*, but the duplicate-brief risk is at agent *output*: a `daily_scan` writes N briefs with fresh `randomUUID`s, crashes before `markDone`, gets requeued, and writes N *more* briefs → the user wakes to doubled "drafted while you slept" briefs. Fix both:
1. Wrap `claim → (await agent) → persist → markDone → signals.processed=true` so the persist+mark run in **one** better-sqlite3 transaction *after* the await returns; a crash rolls back the writes and the event cleanly requeues. Set `signals.processed=true` in the **same** write as the brief insert (today `processSignalReceived` sets it in a separate statement — a crash in between re-briefs the same signal on the next poll).
2. Add `generatedByEventId` to briefs/proposals; recovery deletes prior output of a requeued event before re-running.

**Crash recovery + watchdog.** On boot and every 60s, requeue `processing` rows where `claimedAt < now-STUCK_MS` (`attempts<MAX_ATTEMPTS=3` → `pending`, else `failed`). Set `STUCK_MS` **above** the worst-case throttled agent wall-clock (a Tier-1 12-turn run with bucket waits can legitimately take ~8–10 min) and have the agent **heartbeat `claimedAt`** during a run, so a slow-but-alive run is never reclaimed and re-run concurrently. Fail **immediately** on non-transient errors (JSON parse / validation) instead of burning 3 full agent re-runs; reserve retries for transient (429/5xx/crash) failures.

**Connector backpressure.** Cap signals ingested per `pollOnce` (e.g. 20) with a pagination cursor so a first-time Gmail backfill of hundreds of threads drains over many polls instead of flooding the queue and exhausting the per-user budget before morning. Coalesce multiple new signals from one poll into **one** agent context rather than one agent run per signal.

**SQLite contention (cheap, required).** Set `busy_timeout = 5000` on **both** handles (`src/db/client.ts`, `worker/src/db.ts`) — neither sets it today, and better-sqlite3 throws `SQLITE_BUSY` immediately on writer collision once the API and worker contend the WAL. Keep `/sync` and status reads read-only.

### 4.d Data Model & Sync

**Server SQLite is the single source of truth; iOS SwiftData is a read-mirror/offline cache.** This preserves every `@Query`-driven screen (the constellation pulses, Review-queue drain, Today thread) — the repo writes the cache the same way the local agent used to, so the reactive UI survives the cut-over with near-zero view change.

**v1 ships single-device (no delta-sync protocol).** For one device the client reads the existing tRPC endpoints directly and caches the results; this delivers the security win without the sync machinery. The full delta-sync stack below is **Phase 4** — required only for multi-device/offline-write correctness.

**When sync lands, these are hard prerequisites (not follow-ups) — the adversarial review flagged each as a blocker:**

- **`updatedAt` on every synced table + bump-on-mutate.** Only `chapters` has `updatedAt` today; `todo.toggle` / `brief.setStatus` / `proposal.approve`/`dismiss` bump nothing. A cursor-by-`updatedAt` would silently miss every edit. Add `updatedAt TEXT NOT NULL DEFAULT <ISO-now>` to todos/decisions/entries/briefs/proposals/watchers/signals and set `updatedAt=now()` in every mutating procedure + `writePayload` + `persist.ts`.
- **Timestamp format normalization.** Defaults emit SQLite `current_timestamp` (`YYYY-MM-DD HH:MM:SS`); edits write `toISOString()` (`...THH:MM:SS.sssZ`). Lexically `space < T`, so a string-compare cursor is non-monotonic. A migration normalizes all timestamps to ISO-8601-UTC and switches defaults to ISO. Cursor = `(updatedAt > iso) OR (updatedAt = iso AND id > lastId)`, ordered by `(updatedAt, id)`.
- **Soft-delete with cascade fan-out.** `chapter.delete` is a hard cascade delete — a pull-by-cursor mirror can never observe it and keeps ghost rows forever. Add `deletedAt`, bump `updatedAt`, reads filter `deletedAt IS NULL`, `/sync` returns tombstones. Application-level cascade: a soft-deleted chapter must also tombstone its children in `/sync` (the FK cascade hard-deletes children, which tombstones won't capture).
- **Push idempotency on approve/toggle (not just creates).** `proposal.approve → writePayload` inserts a fresh `randomUUID` todo/decision/entry on every call; at-least-once outbox retry double-files. Make approve transition-guarded — `UPDATE proposals SET status='approved' WHERE id=? AND status='pending' RETURNING` in a txn, run `writePayload` only if a row transitioned — and add `todos.sourceProposalId UNIQUE` with `INSERT … ON CONFLICT DO NOTHING`. Creates carry a `clientRef` UUID for idempotent replay and optimistic-row reconciliation.
- **ID type parity.** iOS `@Model` ids are typed `UUID` (uppercased string), server ids are free-form lowercase text-UUID. Pin a canonical lowercase form on both sides (or make iOS ids `String`) so upsert-by-id can't silently dup. `chapter_links` (no row id) gets a synthetic `fromId|toId|relation` key.
- **One-way, migration-gated `DataSource` flag.** The `.local`/`.server` flag must be **one-way**: `local→server` runs a `sync.bootstrap` upload of local-only rows (assign `clientRef`s, get server ids, rewrite local ids) and **permanently stops** `AtlasAgent` + `Proposal.materialize` for synced types. No `server→local` fallback that resumes local generation against a server-authoritative store — a kill-switch fallback must use a *separate* local store, never the mirror. Two engines writing the same SwiftData store with two ID spaces is split-brain with no merge path.

**Conflict policy:** server stamps `updatedAt` on receipt (ignore client clocks) so a late outbox flush correctly wins as "latest user intent"; agent-owned fields are never client-writable, so the writer sets are disjoint and no merge engine is needed.

**Add `userId` in the SAME migration as `updatedAt`/`deletedAt`** even if v1 ships single-tenant — adding it later forces a third migration and a risky backfill.

### 4.e iOS Client Cut-Over

Minimal-churn: the existing flow is already "write an event → poll to done → read briefs/proposals." Centralize that in one repository and swap its internals.

- **`AtlasRepo` (`@Observable @MainActor`) is the single SwiftData writer.** Screens keep their `@Query` reads verbatim and only swap imperative calls: `repo.submitCapture(...)`, `repo.approve(...)`, `repo.dismiss(...)`, `repo.ask(...)`, `repo.actOnBrief(...)` replace `context.insert(AppEvent)+AtlasAgent.shared.tickOnce()`, `Proposal.materialize(in:)`, and `AtlasLLM.complete()`. ~3-line diff per screen.
- **`AtlasAPI` (`actor`)** is the only network layer — tRPC-over-HTTP, Keychain bearer token, `Retry-After`-aware backoff.
- **Cache-mirror:** `repo.sync()` pulls server rows and upserts into the same `@Model` tables keyed by server `id`; mutations are optimistic-local then write-through then reconciled. This is what preserves `@Query` reactivity.
- **Offline:** reads always serve the cache instantly (never blank); mutations while offline enqueue to a durable `OutboxItem` and flush on reconnect; the existing per-screen empty-state seeds remain the cold-start UI.
- **DELETE / neutralize:** `AtlasAgent.swift` loop, `ClaudeClient.swift` + `GeminiClient.swift` direct Anthropic paths, `BackgroundRefresh.swift`, `ConnectorRunner` + Gmail/Drive fixtures, `AgentTools.swift`. **KEEP:** all 10 `@Model` classes (now the cache), `BriefStructure.swift` (render contract — must stay byte-compatible), `EventKitCalendarSource.swift` (device-only — now a **push** source via `repo.pushCalendarSignals()` → `signal.ingest`, which upserts on `(source, externalId)` so a per-foreground push doesn't create duplicate signals).
- **Security (hard, gating):** delete the Anthropic key from the app entirely; the device bearer token lives in **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never `UserDefaults`. **Remove `NSAllowsArbitraryLoads`** from `Info.plist` (currently `true`) and reject non-`https://` base URLs in `AtlasAPI` — otherwise the bearer token and all personal data can travel cleartext. Do **not** distribute (TestFlight or beyond) any build that still reads `UserDefaults["AnthropicAPIKey"]`; key removal is a prerequisite of distribution, not the last step.
- **`AyumiSettings`:** remove the Anthropic-key field; show server URL, connection/sync status, and a **server-reported** budget readout (the editable on-device `LLMBudget` cap is advisory only and is removed from shipping Settings).

### 4.f Hosting / Ops / Security on Oracle Free VM

- **One Oracle `VM.Standard.A1.Flex` ARM VM** (provision 2 OCPU / 12 GB of the 4/24 always-free budget — for build headroom, not reclaim avoidance; see Risks). Runs Next.js (`pnpm start`, **bound to `127.0.0.1:3000`**), the worker (`tsx worker/src/index.ts`), and the shared `/opt/atlas/data/atlas.db`. Truly $0 for compute; OCI's 10 TB/mo egress is enormous headroom for JSON.
- **Caddy :443** terminates auto-TLS (Let's Encrypt) and reverse-proxies to `127.0.0.1:3000`. Security list opens **only 80 + 443**; 3000 stays closed at both the security list and host `ufw`; SSH restricted to your IP. Set HSTS + a request-body-size limit at the proxy.
- **systemd** `atlas-web.service` + `atlas-worker.service`, `Restart=always`, `EnvironmentFile=/etc/atlas/atlas.env` (root:atlas, `0600`) — the **only** place `ANTHROPIC_API_KEY` and `AUTH_TOKEN_PEPPER` exist.
- **Auth:** new `device_tokens { id, userId, tokenHash (sha256(token + pepper)), label, createdAt, lastSeenAt, revokedAt }`. Store **only the hash** (resolve the contradiction in favor of hashing — a plaintext-PK token table hands out live credentials on any DB/backup leak, and litestream replicates the DB to a second location). `protectedProcedure` + auth middleware in `src/server/trpc.ts`; `createContext` resolves the bearer header to a `userId`. **No `DEFAULT_USER_ID` fail-open** — an absent/unknown token returns 401. Single-tenant bootstrap = **seed one device token at deploy time** (printed once to the operator), not "no token ⇒ default user." Disable open `register` for the single-user MVP; add a per-IP limiter + global daily org-spend ceiling before it's ever opened.
- **Per-user data isolation (gating before a 2nd token exists):** thread `ctx.userId` into every query/mutation as a `WHERE` predicate and every insert. Without it, the second device reads and mutates the first user's rows. Add `userId` in the same migration as `updatedAt`/`deletedAt`.
- **Connector OAuth tokens** (when connectors land): encrypt refresh tokens with a key from `/etc/atlas/atlas.env` (AES-GCM / libsodium secretbox) before insert, scoped per `userId`; the encryption key is never in the DB; replicate only ciphertext. These grant full inbox/Drive access — higher-value than the app's own token.
- **`.gitignore` fix (one-liner, do now):** today it ignores only `.env*.local`, so `.env` / `.env.production` are committable. Change to ignore `.env` and `.env.*` with `!.env.example`, and add a `gitleaks` pre-commit scan. The key must never enter git history.
- **Backups:** nightly `sqlite3 .backup` (1 PUT/day, unambiguously $0) is the primary durability mechanism; litestream→OCI Object Storage is optional and, if used, runs at a 30–60s sync interval to stay under OCI's free *request* cap (the binding constraint is PUT count, not the 20 GB storage). Restore = `litestream restore` or the nightly file.
- **Deploy** (`/opt/atlas/deploy.sh`): `git pull && pnpm install --frozen-lockfile && pnpm build && <migrate-only> && systemctl restart atlas-web atlas-worker`. **Split migrate from seed** — `src/db/migrate.ts` currently auto-runs `seed` + `seed-v2` on every invocation; the deploy path must call a migrate-only entrypoint and gate seeding behind `ATLAS_SEED=1`, or demo data can leak into the live DB.
- **Health:** public `/api/health` returns minimal `{ok:true}`; version/heartbeat detail is auth-gated (don't hand an unauthenticated liveness+version oracle to the internet).

---

## 5. Phased Cut-Over Plan

Each phase is independently shippable. Phase 0 stops the breach with **zero** iOS change.

### Phase 0 — Throttle so nothing re-breaches · effort **L** · server-only
Build `gateway.ts` + `config.ts` + `buckets.ts` + the `usageLedger` table. Default to **Tier-1** bucket sizes; clamp from `anthropic-ratelimit-*-limit` headers on every response. Rewire `worker/src/agent/loop.ts:92` to `runAgentLoop` (pin `claude-sonnet-4-6`, add `cache_control` to system+sorted-tools, route through buckets) and `src/app/api/ask/route.ts:63` to `createMessage({route:'one_shot'})` (Haiku). Add `busy_timeout=5000` to both DB handles. Assert at startup that the agent prefix has `cache_control` (launch blocker). **Exit:** with the worker running 24/7 under synthetic load, zero `429`s reach the org limit; `cache_read_input_tokens > 0` on repeated agent turns; a forced `429` pauses the bucket and resumes after `Retry-After`; `usageLedger` survives a worker restart.

### Phase 1 — Worker reliability · effort **M** · server-only
Split `index.ts` into `queue.ts`/`scheduler.ts`/`runtime.ts`. Add `events.claimedAt`/`attempts`/`dedupeKey` (unique partial index) via a Drizzle migration. Implement output-idempotency (single txn, `generatedByEventId`, `signals.processed` in the same write), boot/watchdog recovery with heartbeat, the 06:00 catch-up check, connector backpressure, and graceful `SIGTERM` drain. Fill the `forward_drift_scan`/`time_trigger` TODO branches. **Exit:** kill -9 mid-`daily_scan` produces **no** duplicate briefs on restart; a scan scheduled while the VM was suspended past 06:00 runs on next boot exactly once; a 200-signal backfill drains over many polls without exhausting the daily budget.

### Phase 2 — Auth + key removal (the security cut) · effort **M** · gates client cut-over
Add `device_tokens` (hashed), `protectedProcedure`, `userId` column on all user-owned tables (same migration adds `updatedAt`/`deletedAt` to avoid a third migration) with `WHERE userId` scoping threaded everywhere. Seed one operator token. Add Zod validation + size caps to `ai.ask`. Fix `.gitignore` + add `gitleaks`. **Exit:** every Anthropic-touching endpoint 401s without a valid token; a second seeded token cannot read the first user's rows; `git check-ignore .env .env.production` both return ignored.

### Phase 3 — iOS thin client (behind a flag) · effort **L** · client + server
Add `AtlasAPI` + `AtlasRepo` + Keychain + DTOs; rewire the 6 screens to `repo.*`; add `brief.act` + `ai.ask` (as an enqueued `one_shot` job) + `signal.ingest` server-side. Remove `NSAllowsArbitraryLoads`; delete the on-device key and direct-Anthropic paths from any distributed build. Ship behind `DataSource` default `.server` with a developer-only `.local` fallback (separate store). **Exit:** Capture/Review/Search/Brief-act all round-trip through the server on a real device with no Anthropic key present; ATS enforced; TestFlight build contains no `UserDefaults["AnthropicAPIKey"]` read.

### Phase 4 — Multi-device delta-sync · effort **L** · deferred
Timestamp normalization migration; `clientRef`; soft-delete + cascade fan-out + tombstones; push idempotency keys on approve/toggle; ID-type parity; `sync.pull`/`sync.bootstrap` (`protectedProcedure`); `OutboxItem` queue; one-way migration-gated flag. **Exit:** two devices converge after offline edits with no duplicates, no ghost rows, no lost toggles; a 500-row single-tick burst drains across pages with no skips/repeats.

### Phase 5 — Real connectors + (optional) push · effort **L–XL** · deferred
Real Gmail/Drive/Calendar OAuth with per-user encrypted refresh tokens, replacing fixtures; iOS keeps EventKit as a push fast-path. **APNs is explicitly out of v1** (see Risks — it needs a paid Apple Developer account, so it can't be "truly $0"); poll-on-foreground + poll-after-push is the v1 delivery mechanism. If "drafted while you slept" *push* becomes a launch requirement, scope a minimal `content-available` APNs nudge here. **Exit:** a real inbox produces signals → proposals overnight; calendar events from EventKit and Google Calendar de-dupe to one source of truth.

---

## 6. Risks & Mitigations

**Resolved blockers (must be implemented as specified, not deferred):**

| Risk | Mitigation | Phase |
|---|---|---|
| **Unknown org tier → Tier-2 buckets re-breach on Tier 1** | Default config to Tier-1 numbers; clamp every bucket to `min(configured, header-reported-limit)` on every response; cache enforcement asserted at startup | 0 |
| **Duplicate overnight briefs** (event-layer dedupe doesn't cover agent output re-run) | Single txn around persist+mark; `generatedByEventId`; recovery deletes prior output; `signals.processed` set in the same write | 1 |
| **In-memory buckets split across 2 processes admit ~170%** | `ai.ask` enqueues a `one_shot` job the worker drains; only the worker calls `messages.create` (single authoritative bucket) | 0/3 |
| **`SQLITE_BUSY` under concurrent API+worker writes** | `busy_timeout=5000` on both handles; `WORKER_CONCURRENCY=1` for writes | 0/1 |
| **Fail-open `DEFAULT_USER_ID`** = open Anthropic proxy + full data hole | No fallback user; 401 on absent/unknown token; seed one operator token | 2 |
| **No per-row `userId` scoping** = 2nd device reads/mutates 1st user's data | `userId` column + `WHERE userId` everywhere, same migration as `updatedAt` | 2 |
| **Plaintext token / committable `.env` / ATS off / on-device key** | Hash tokens with pepper; `.gitignore` `.env*` + gitleaks; remove `NSAllowsArbitraryLoads`; delete on-device key before any distributed build | 2/3 |
| **Daily scan silently skipped** on suspend/NTP/restart | Wall-clock catch-up check on every wakeup + boot, gated by `dedupeKey` | 1 |
| **Sync loses edits / ghost rows / double-files** | `updatedAt`+bump, ISO normalization, soft-delete+cascade, transition-guarded approve + unique `sourceProposalId` | 4 |

**Accepted / deferred (with rationale):**
- **Poll-only delivery in v1.** A suspended iOS app can only be woken by APNs, and APNs requires a **paid ($99/yr) Apple Developer account** — incompatible with "truly $0." So overnight briefs land when the user next foregrounds the app. This is acceptable for v1; gate any "we notify you" marketing claim on Phase 5's optional APNs nudge.
- **Oracle idle reclaim.** Provisioning fewer OCPUs does **not** avoid reclaim — low CPU *utilization* (<20% p95 over 7 days) does. The reliable fix is upgrading the tenancy to **Pay-As-You-Go** (still $0 under always-free limits), which exempts the instance from idle-reclaim and also dodges the "Out of Host Capacity" creation failure. A light keep-alive task is the fallback.
- **Connector breadth.** Gmail/Drive OAuth is greenfield (the v0.2 "real OAuth in v0.3" was never built); only EventKit is real today. Deferred to Phase 5; fixtures remain a demo/offline mode.

**No unresolved blockers remain** for Phases 0–3 (the security + reliability cut) provided the resolved-blocker mitigations above are implemented in-phase rather than deferred.

---

## 7. Open Decisions for the User

1. **Confirm the org tier before pinning bucket sizes.** The design ships Tier-1-safe and self-raises from headers, so this isn't blocking — but reading the real limits from the Console Limits page / Rate Limits API lets us start the buckets at the right ceiling instead of ramping up. *Recommendation: confirm once; keep header-clamp regardless.*
2. **Multi-device, or single-device for v1?** Single-device drops the entire Phase 4 sync stack (timestamp migration, soft-delete, `clientRef`, outbox) off the critical path and ships the security win far sooner. *Recommendation: single-device v1; add `userId` to the schema now anyway so multi-user is a non-migration later.*
3. **Push vs poll for "drafted while you slept."** Poll-only is $0 and ships now; real background push needs a $99/yr Apple Developer account + an APNs sender on the VM. *Recommendation: poll for v1; revisit APNs only if push is a hard launch requirement.*
4. **Auth onboarding for the first device.** Operator-minted seed token (simplest, fits single-user) vs a one-time pairing code typed into the app vs email magic-link. *Recommendation: operator-minted seed token for v1; pairing code when multi-user lands.*
5. **Agent `effort` level for overnight runs.** `claude-sonnet-4-6` supports `effort` (`low`/`medium`/`high`). The overnight agent default of `high` raises latency + OTPM. *Recommendation: start the agent route at `medium` to conserve the OTPM bucket; A/B against brief quality before committing.*
6. **Domain/DNS for Caddy auto-TLS.** Let's Encrypt won't issue for a bare IP. *Recommendation: a subdomain you control, or DuckDNS, pointed at the VM's public IP.*
