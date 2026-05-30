# Ayumi — Bringing It To Life: Live-Data Roadmap

> Produced by a multi-agent analysis (11 agents) that verified every load-bearing claim against the real code: the six new `Views/Ayumi/*.swift` screens have **0 `@Query`** (all seeded arrays), the agent loop is attached and running, `Proposal` has `sourceSignalIdsJSON` but no `sourceEventID`/`actionKind`, `Brief` has no source-signal field, `CapturePayload` has no `intent`, `isConfigured` == Anthropic key present, the daily scan is gated on `hour == 6` (a dead window), connectors are fixtures, `BriefStructure` has 10 cases but no `Citation`, and there is no `Person` model.

## 1. Executive summary

The hard parts are already built. The agent loop (`AtlasAgent` actor, 30s foreground tick, crash recovery, watcher cadence) is attached to the SwiftData container at `AtlasApp.swift:29/71` and runs against the default **`ClaudeClient`** (Anthropic key in `UserDefaults["AnthropicAPIKey"]`, `ClaudeClient.swift:24`). The write tools (`create_brief`/`create_proposal`/`create_watcher`), `Proposal.materialize(in:)`, the `BriefStructure` 10-section contract (`Lib/BriefStructure.swift:19`), and a **proven** capture round-trip (`CaptureSheet.swift:192-231`) all exist and produce real records. `Seed`/`SeedV2` already populate chapters, links, watchers, three full briefs, and pending proposals on first launch.

What's missing is almost entirely **wiring**: grep confirms **zero `@Query` and zero `modelContext` across all six `Views/Ayumi/*.swift`** — every screen renders `static let seed` arrays into a store nothing in the new UI observes. Beyond wiring, the work is (a) a handful of *additive, lightweight-migration* model fields, (b) replacing fixture connectors with on-device EventKit/Speech sources, and (c) one timing fix.

**The 2-3 biggest levers:** (1) bind the six screens to the models already populated by Seed — this alone lights up Review, Chapters, Search-local, and most of Brief with no schema change; (2) wire Capture/Today's compose bar to the existing `AppEvent → tickOnce() → poll` loop; (3) fix the dead overnight scan (`maybeRunTimeTriggers` gates on `hour == 6` IST — `AtlasAgent.swift:197` — which the app is almost never foregrounded for, so the "while you slept" surface can never populate).

**Single biggest unknown/risk:** the **sync architecture**. The connectors analysis found two fully-disconnected ingestion stacks (the `/worker` Node process and the self-contained iOS runtime) that *never talk*, and the iOS app is explicitly designed to be the runtime, not a thin client (`AtlasAgent.swift:9-12`). Decide *before Phase 4* that SwiftData is the on-device source of truth and the server is only an OAuth token broker — not a system of record to sync against. Get that wrong and you maintain two agent loops forever.

---

## 2. The shape of it

```
  On-device connectors          SwiftData (on-device source of truth)         Worker / Next.js
  EventKit · Speech ───┐        ┌─ Chapter, ChapterLink, Watcher              (legacy / web demo)
  Gmail/Drive REST ────┼─write─▶│  Brief(structureData), Proposal, Signal     · /api/ask (one-shot
        ▲              │        │  Entry, Decision, Todo, AppEvent              chat, NOT RAG)
        │ access       └────────┤                                             · token broker (future,
        │ tokens only           │            ▲      writes Brief/Proposal       OAuth only — NOT a
   token broker ◀────────┐      ▼            │                                  data store to sync)
   (tiny Next.js)        │   AtlasAgent loop ─┘
                         │   (30s tick · ClaudeClient default · AgentTools)
                         │            ▲
                         └── @Query ──┴── the six Ayumi screens (read) + compose bars (write AppEvent)
```

The **LLM stays rented**: connectors only produce `Signal` rows; all reasoning runs through `AtlasLLM.run(...)` against the provider-neutral seam (`LLMClient.swift:71`), Claude by default. Model additions only give the agent richer typed slots to write into — they never change that posture.

**Where each screen's data comes from:**

| Screen | Source | Read shape |
|---|---|---|
| **Today** | `Brief` (surfaced) + `AppEvent` (captures, in-flight) | derived thread (no Turn model — see §6) |
| **Brief** | one `Brief`, decode `structureData` → `BriefStructure` | the existing `BriefRenderer` contract, reskinned |
| **Capture** | writes `AppEvent(.captureReceived)`; reads back `Proposal`s | the proven `CaptureSheet` loop |
| **Chapters** | `Chapter` + `ChapterLink` + active `Watcher` + latest `Brief` | port of `ConstellationView` |
| **Review** | pending `Proposal` | `materialize(in:)` / `.dismissed` |
| **Search** | `Brief`/`Entry`/`Decision`/`Todo`/`Chapter`/`Signal` (in-memory) + one-shot ClaudeClient answer | `SearchEngine` + grounded `complete()` |

---

## 3. Phased plan

> **The one constraint every phase obeys:** `@Query #Predicate` cannot see computed enum wrappers. Filter on the **stored** raw string — `$0.statusRaw == "surfaced"` / `"pending"` / `"active"` — exactly as the existing handlers and `TodayView.swift:7-10` do. SwiftData `#Predicate` also can't reach into JSON `Data` blobs or do case-insensitive `contains` — hence in-memory filtering for Search.

### Phase 0 — Bind to existing data — **the quickest win**
**Goal:** replace seeded arrays with `@Query` over models Seed/SeedV2 already populate. No new models, no agent calls, no network. The container is already in scope inside `AyumiRoot` (`PageShell.swift:84` injects router+halo; `.modelContainer` is on the `WindowGroup`, `AtlasApp.swift:71`), so adding `@Environment(\.modelContext)` + `@Query` "just works."

**Exact work:**
- **Review** (`ReviewScreen.swift`) — add `@Query(filter: #Predicate<Proposal>{ $0.statusRaw == "pending" }, sort: \.createdAt, order: .reverse)`. Map `Proposal`→card: `summary`→said, `reasoning`→why, `sourceLabel`+`sourceMeta`→cite, `createdAt`→when; tone/labels **derived from `proposal.type`** (todo→draft, decision/journal→filed, chapter→held). **Split the two buttons** — today both call the same `resolve(item)`, so decline behaves like approve (a real bug): approve → `proposal.materialize(in: context)`, decline → `proposal.status = .dismissed; proposal.decidedAt = Date()`. Delete `queue.removeAll`; let `@Query` drive removal inside `withAnimation`; keep all Halo choreography. **(S)**
- **Chapters** (`ChaptersScreen.swift`) — three `@Query`s (chapters / links / active watchers, the `statusRaw == "active"` predicate proven in `TodayView.swift:9`). Map `Chapter`→node, `ChapterLink`→edge (reuse `Constellation.swift:402` edgeColor + conflict-dash). **Node positions: derive deterministically** by porting `ConstellationView.ensureSeeded()`'s quadrant seeds (`Constellation.swift:83-88`) into the existing 350×340 `sx/sy` space — no schema change. Pulse = `status == .active && hasActiveWatcher` (in-memory filter). Detail strip from `purpose`, `entries.count`, watcher count, `cadenceLabel`. **(M)**
- **Search-local** (`SearchScreen.swift`) — add `@Environment(\.modelContext)`; replace `static let corpus` with a live builder over `@Query` of `Brief`/`Entry`/`Decision`/`Todo`/`Chapter` (map Entry+Decision→`.note`, the label already says "NOTES & DECISIONS"). Keep `static answers` keyword table powering the JadeCard (no RAG yet). **Drop the People chip** (no `Person` model). Keep static corpus as the empty-DB fallback. **(S)**
- **Brief read** (`BriefScreen.swift`) — add `@Query(filter: #Predicate<Brief>{ $0.statusRaw == "surfaced" }, sort: \.surfaceAt, order: .reverse)`; pick `surfaced.first`; decode `structureData`→`BriefStructure` once (copy `BriefRenderer.structure`); bind the six existing sections to the decoded `*Data`. Predictions: render `ConfidencePill` from the existing `high/medium/low` enum via a `defaultScore()` map — no schema change. Keep `Receipt.canned` for cites for now. **(M)**

**Alive at the end:** Review (real approve/decline), Chapters (real constellation breathing off seeded watchers/briefs), Search list, and Brief all render live SwiftData. With no API key this still works — `SeedV2` runs regardless of `isConfigured`, so the store is never empty.

### Phase 1 — The capture & review loop
**Goal:** wire Capture and Today's compose bar to the real loop so the queue fills from user input; Review becomes the real downstream.

**Exact work:**
- **Capture** (`CaptureScreen.swift`) — delete the fake `asyncAfter(2.2s)` (`:187`). Replace `send()` with the `CaptureSheet` pattern: write `AppEvent(.captureReceived, CapturePayload(text, kind:"auto", chapterID: activeChapterID))`, `await AtlasAgent.shared.tickOnce()`, poll `AppEvent.status` to `.done`/`.failed`, then fetch the proposals this run created and render the three `extractedItem` cards from them. `halo: .thinking` on send → `.delivered` on done. **(M)**
- **Today compose** (`TodayScreen.swift`) — same loop on `send()`, with `intent: "ask"` so the user bubble renders in the thread; `halo .thinking` on send (the seed wrongly fires `.delivered` immediately), `.delivered` when the `AppEvent` reaches `.done`. **(M)**
- **Model add — `Proposal.sourceEventID: UUID?`** (Gap H) so Capture/Today show *this* run's proposals, not the whole queue (the no-migration interim is `createdAt >= sendStartedAt && statusRaw == "pending"`, which races against connector writes). Thread it through `AgentTools.registry(for:scopeChapter:sourceEventID:)`, `CreateProposalTool`, `CaptureHandler`, and `fallbackPersistAsProposal`. **(S)**
- **Dormant fallback** — already end-to-end: with no key, `CaptureHandler` guards `AtlasLLM.isConfigured` (`EventHandlers.swift:99`) and `fallbackPersistAsProposal` writes a pending `Proposal` ("…add a Claude (Anthropic) API key in Settings…"), still marking the event `.done` so the poll resolves. Add a client-side floor so the result turn is never empty. **(S)**

**Alive at the end:** capture → real `AppEvent` → real agent (or dormant fallback) → real `Proposal`s in Review. The full capture→reason→review→materialize loop is live. **Needs the Anthropic key for reasoning** (dormant fallback otherwise).

### Phase 2 — Real briefs & the Today thread
**Goal:** the overnight digest actually generates, and the Today thread reads as a live conversation.

**Exact work:**
- **Fix the dead overnight scan (highest impact)** — replace the `hour == 6` gate in `maybeRunTimeTriggers` (`AtlasAgent.swift:197`) with "first foreground after local ~5am if no scan ran today" (keyed on `lastDailyScanStamp`), plus a BG-refresh catch-up that enqueues `dailyScan` when the stamp is stale. Without this, "while you slept" never populates. **(S)**
- **Today thread VM** — new `Views/Ayumi/TodayThreadModel.swift`: a `@MainActor @Observable` that merges surfaced `Brief`s (Ayumi turns + `BriefCapsule`) with `capture_received` `AppEvent`s (user turns, filtered to `intent == "ask"`) into one time-ordered `[ThreadItem]`, plus a live `ThinkingTurn` when any `AppEvent` is `.pending`/`.processing`. Use one `@Query` per type purely as a change-trigger that calls `reload()`. **Derive the thread; do not persist a Turn model** (§6). **(M)**
- **`CapturePayload.intent: String?`** (`"ask"` | `"file"`) — splits conversational asks (render as `UserTurn`) from filing captures (route to Review). No SwiftData schema change — `payloadJSON` is an opaque blob. **(S)**
- **Brief enrichment** — add optional, additive fields: `Brief.sourceSignalIdsJSON` (symmetric to `Proposal`'s, for the "6 sources" line), `Brief.threadProse`/`framing`, `Brief.sourceCount`; `Citation` + `cite`/`traces` on `TimelineData.Item`/`TacticalData`/`QuoteData` and `score: Double?` on `PredictionData.Item` (all **inside the `structureData` blob → zero SwiftData migration**, old blobs decode with `nil`). Thread the new args through `CreateBriefTool` + `AtlasSystemPrompt`. Replace `Receipt.canned` with `Citation`-derived receipts that resolve real `Signal`s by `signalID`. **(M)**
- **A first-class morning digest** — give `TimeTriggerHandler` an explicit instruction (or a `compose_morning_digest` tool) to triage new signals, draft ≤N briefs for near-term milestones, and write the "Handled X overnight" summary line. **(M)**
- **`NavRouter.selectedBriefID` + `openBrief(_:)`** so Today's `BriefCapsule.onOpen` deep-links the exact `Brief` and `BriefScreen` resolves it (fetchLimit 1) with `surfaced.first` fallback. **(S)**

**Alive at the end:** the morning brief queue generates on first daily open; Today is a live, persistent conversation; the Brief screen shows real citations and deep-links. (**Persona note:** `PersonBriefData` should *not* be created — the existing `BriefStructure` + `PersonData` already are it; do not fork a parallel model.)

### Phase 3 — Search & RAG
**Goal:** real on-device retrieval + a grounded answer card.

**Exact work:**
- New `Search/SearchEngine.swift` — `search(_:scope:)` fans across the 6-7 model types with a **coarse predicate + in-memory `.range(of:options:.caseInsensitive)`** (the house style in `GmailSearchTool`/`PersonLookupTool`), ranked (title>body, then recency), grouped, capped ~8/bucket. Volume is tiny (one user). **(M)**
- **Grounded answer** — add `func complete(system:user:maxTokens:)` to the `LLMClient` protocol + `ClaudeClient` (reuse `sendOnce`'s HTTP block with **no `tools` key** so it returns on the first turn) + `GeminiTextClient` (keep it swappable). `SearchEngine.answer(for:hits:)` stuffs the top-8 snippets into a prompt → 1-2 sentence Ayumi-voice answer. **Do NOT route search through `AppEvent`** — it's a read with an ephemeral answer; the full agent loop is the wrong shape and `Event.swift` has no `.search` type. **(M)**
- **Halo honesty** — rewire `SearchScreen`'s `settle()` (currently a fixed 0.65s timer) to a cancellable debounced `Task` (280ms): `.thinking` on keystroke, instant local rows, `.delivered` only when the *real* answer lands, `.idle` if cleared/no-answer. Gate the paid call on `query.count >= 3 && !hits.isEmpty && isConfigured`; cache by `(query, scope)`; single attempt + ~8s timeout (not the agent's 3-retry/180s budget). **(S)**

**Alive at the end:** search list and answer card both live; offline/no-key degrades to grouped results with no card.

### Phase 4 — Ingestion & connectors — **the biggest lift**
**Goal:** real `Signal`s instead of Swift fixtures. **Architecture decided first (see §5): on-device connectors are default; server is OAuth broker only.**

**Exact work:**
- **Phase 0 prereqs** — add to `project.yml`/Info.plist: `NSCalendarsUsageDescription`, `NSRemindersFullAccessUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `UIBackgroundModes: [fetch, processing]`, `BGTaskSchedulerPermittedIdentifiers: [com.atlas.app.refresh]` (ID already defined, `BackgroundRefresh.swift:13`). **(S)**
- **Calendar via EventKit** (ship first; zero server) — new `Agent/Connectors/EventKitCalendarSource.swift`; map `EKEvent`→ the existing `CalendarConnector.Event` struct → `Signal(source:.calendar)` + `AppEvent(.signalReceived)`, **keeping the exact dedupe/enqueue shape** from `EventHandlers.swift:431-440`. `calendar_query` already reads these rows untouched → agent and Today light up immediately. **(M)**
- **Voice memos** — `AVAudioRecorder` + `SFSpeechRecognizer`; feed the transcript straight into the existing capture loop (`CapturePayload`, `kind:"auto"`) — reuses `CaptureHandler`, no new handler. **(M)**
- **Gmail + Drive** — tiny Next.js token broker (`/api/oauth/google`) returning short-lived access tokens; refresh token in **Keychain**, never the client secret in the binary. `GmailSource`/`DriveSource` map REST responses to the existing `Message`/`Doc` structs → `Signal` + `AppEvent`. `gmail_search` reads them untouched. **(L)**
- **Wire-up** — `ConnectorRunner.pollOnce` (`EventHandlers.swift:361`, the only call site, driven 15-min from `maybePollConnectors`) calls the live sources gated by granted permissions/tokens. Delete the fixture arrays. BG ingestion is then free via the existing `BackgroundRefresh` → `tickOnce`. **(S)**

**Alive at the end:** Today/Brief/Review fill from the user's real calendar, voice, and (with the broker) email/drive. Messages/SMS is **out of scope** — iOS gives no read access.

### Phase 5 — Background, notifications, polish
**Goal:** runs while the app sleeps; bounded cost; full drill-in.

**Exact work:**
- BGAppRefresh schedule already exists; ensure overnight catch-up (Phase 2) fires on wake. **(S)**
- **Cost/rate guards — none exist today** (grep confirms no `budget`/`rateLimit`/`throttle` in the agent path). Add: (1) **prompt caching** — hoist the immutable `AtlasSystemPrompt` + tool decls out of the loop and add Anthropic `cache_control` (the single biggest token lever; re-paid every iteration today); (2) **coalesce signal fan-out** — `SignalReceivedHandler` currently runs one full LLM pass *per signal*; batch into one "triage these N signals" run + a cheap local pre-filter; (3) a **per-day run budget** actor; (4) a **re-entrancy guard** (`if isTicking { return }` — foreground 30s loop + BG refresh can overlap and double-drain); (5) a real **per-request URLSession timeout**. **(M)**
- Push notifications for surfaced briefs; drill-in nav (Review/Search/Chapters → Brief). Materials-checkbox persistence (re-encode `structureData`). `.draftReply` "Send it" → `AppEvent(.briefActedOn)` + a real send tool. **(M)**

**Alive at the end:** Ayumi works overnight, within a cost budget, fully navigable.

---

## 4. Model additions

All additive — **either a new `@Model` or an *optional/defaulted* field → lightweight automatic migration** (just add new `@Model`s to the container `Schema`). Fields *inside* `structureData` need **no SwiftData migration at all** (opaque blob; old data decodes with `nil`). The store is on-disk (`isStoredInMemoryOnly: false`), so never add a non-optional/no-default field, rename, or change a relationship — those are destructive.

| # | Where | Swift | Migration | Phase |
|---|---|---|---|---|
| 1 | `Proposal.swift` | `var sourceEventID: UUID?` — back-link to spawning `AppEvent` | optional → lightweight | 1 |
| 2 | `CapturePayload` (`AtlasAgent.swift:226`) | `var intent: String? = nil` — `"ask"` \| `"file"` | none (blob) | 2 |
| 3 | `Brief.swift` | `var sourceSignalIdsJSON: Data?` (+ `[UUID]` accessor); `var threadProse: String?`; `var framing: String?`; `var sourceCount: Int = 0` | optional/default → lightweight | 2 |
| 4 | `Lib/BriefStructure.swift` | `struct Citation: Codable`; add optional `cite: Citation?` to `TimelineData.Item`/`QuoteData`, `traces: [Citation]?` to `TacticalData`, `score: Double?` to `PredictionData.Item` | **none** (blob) | 2 |
| 5 | `Proposal.swift` | `var actionKindRaw: String?` + `ProposalActionKind` enum {`draftReply`,`filed`,`held`,`todoDrafted`}; optional `approveLabel`/`declineLabel`; `proposedText: String?` | optional → lightweight | 1.5/full Review |
| 6 | `ProposalStatus` | add `case held` (alert awaiting routing) | enum add → lightweight | full Review |
| 7 | `Chapter.swift` | `@Relationship(.nullify, inverse:\Watcher.chapter) var watchers; @Relationship(.nullify, inverse:\Brief.chapter) var briefs`; optional `var nodeX: Double?` / `nodeY: Double?` | relationship+optional → lightweight (use `.nullify`, **not** `.cascade`) | full Chapters |
| 8 | `NavRouter` (`AyumiNav.swift`) | `var selectedBriefID: UUID?` + `func openBrief(_:)` | not persisted | 2 |
| 9 | `Models/Person.swift` (**new**) | `@Model Person { id, name, role?, email?, notes?, createdAt }` + `Brief.personID: UUID?` | new model → lightweight; **register in container Schema** | **deferred** |
| 10 | `LLMClient` protocol + `ClaudeClient`/`GeminiTextClient` | `func complete(system:user:maxTokens:) async throws -> String` | not persisted | 3 |

> **Explicitly NOT added:** a `Turn`/thread model (the thread is derived — §6); a `PersonBriefData` type (the existing `BriefStructure`+`PersonData` already are it); a queryable `Receipt @Model` (the in-blob `Citation` covers the UI). Promote `Person`/`Receipt` to real models only when you need cross-brief dedup or auditable provenance.

---

## 5. Cut-line / risks

**Decide first — the sync architecture.** Confirm: **SwiftData is the on-device system of record; the server is an OAuth token broker only, never a data store to sync against.** The `/worker` Node stack is legacy/redundant (the iOS app has its own full agent loop and tool registry by design, `AtlasAgent.swift:9-12`). Do **not** build worker→DB→iOS sync — it would mean two agent loops, fight SwiftData identity/`@Attribute(.unique)`, and is absurd for calendar/voice which are device-local anyway. `/api/ask` is **one-shot chat, not RAG** — useful only as a template; don't route on-device search through it (the records live in SwiftData, not Postgres).

**Defer:** the standalone `Person` model (ship Brief/Search by reading `PersonData` out of `structureData`; drop the People chip until a People surface exists); promoting `Receipt`/`Citation` to a queryable model; the `/worker` decommission; Gmail/Drive (Phase 4's long pole — Calendar+Voice deliver most of the value with zero server); semantic/`NLEmbedding` search (substring retrieval is real RAG-enough for one user's store); Messages/SMS (impossible on iOS).

**Risks:** (1) **Cost** — no budget guards exist; uncapped signal fan-out (one LLM run per fixture signal today) becomes real spend when connectors go live, and the static prompt prefix is re-billed every loop iteration. Land prompt caching + signal-batching + a per-day budget **before** Phase 4. (2) **Privacy** — the Anthropic key sits in `UserDefaults`, not Keychain; OAuth refresh tokens *must* be Keychain. (3) **Cold-start emptiness** — gate every screen on `items.isEmpty` with a welcome state and keep seeded demo copy behind a `demoMode` flag so design review survives. (4) **`@Query` churn** — Today is the launch screen; every `@Query` needs a predicate + `fetchLimit`, never a whole-table fetch.

---

## 6. First PR — the smallest end-to-end "it's alive" slice

**Capture → reason → Review → materialize, with the dormant fallback.** This is the tightest loop that proves live data both writes and reads, works with no key, and touches the fewest files.

**Ship:**
1. `Views/Ayumi/ReviewScreen.swift` — add `@Environment(\.modelContext)` + `@Query(filter: #Predicate<Proposal>{ $0.statusRaw == "pending" }, sort: \.createdAt, order: .reverse)`. Map `Proposal`→card (tone/labels derived from `.type`). **Split the two buttons** (fix the approve/decline same-handler bug): approve → `materialize(in:)`, decline → `.dismissed`. Let `@Query` drive removal; keep the Halo choreography.
2. `Views/Ayumi/CaptureScreen.swift` — delete the fake `asyncAfter(2.2s)`; wire `send()` to the proven loop: write `AppEvent(.captureReceived)` → `AtlasAgent.shared.tickOnce()` → poll status → render the resulting `Proposal`s. `halo: .thinking`→`.delivered`. Add the empty-result floor.

**No model changes, no network, no new files.** With a key: capture → agent → 1-3 real proposals → Review → approve → real `Todo`/`Decision`/`Entry`/`Chapter` via `materialize`. With no key: `fallbackPersistAsProposal` writes one pending proposal and the same loop completes. Two files prove the entire spine is alive.

**Reuse, don't rebuild:** capture loop `Views/Capture/CaptureSheet.swift:192-231`; predicates `Views/Today/TodayView.swift:7-10`; materialize `Models/Proposal.swift:121`; legacy Review path `Views/Review/ReviewQueueView.swift`; dormant fallback `Agent/EventHandlers.swift:136`; engine gate `Agent/LLMClient.swift:69`.
