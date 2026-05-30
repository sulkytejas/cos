# Atlas / Ayumi — Performance Engineering Review

> Method: static performance review (no Xcode/Instruments on the review machine).
> 6 review dimensions fanned out across the codebase → 62 findings → each
> adversarially verified against the real code by independent skeptics →
> **59 confirmed** (5 high, 20 medium, 34 low). Top structural claims (H1/H3/H4/H5)
> additionally re-verified by hand. The "How to actually measure" section at the
> bottom tells you how to confirm each top finding on a real device.

## Executive summary

The app is functionally rich but its primary surface (Today) is a sustained-redraw
machine: the always-mounted `TempoNow` hero alone stacks **six concurrent
`TimelineView` loops** (one 1s periodic wrapper + five 30–60fps animation loops),
and with `CompassDial`, up to ~6 `WatcherIcon` radars, and two `.breathing()` text
scalers in the same non-lazy `ScrollView`, **Today runs ~10–15 independent
display-link-driven invalidation sources at once** — none of which pause when
scrolled off-screen or when the scene backgrounds. The three things that matter
most: (1) **collapse and gate the animation loops** (visibility + scenePhase +
reduceMotion), (2) **kill the unused/whole-table `@Query`** that turn every
background-agent write into a full Today re-render and refetch, and (3) **get
formatter allocation and image decode/crop off `body` and off `@MainActor`**. None
of these need new features — they're mechanical, and they're on the hottest paths
in the app.

---

## Implemented in this branch (2026-05-30)

The animation refactor + high-ratio quick wins are applied (not yet device-tested — no Xcode on the review machine; build + profile on a dev Mac):

- **New `AmbientTimeline` primitive** (`Views/Components/AmbientTimeline.swift`) — the only sanctioned decorative-motion loop. Gates on `scenePhase != .active`, Reduce Motion, Low Power Mode, and a caller `active:` visibility flag. Replaces every `TimelineView(.animation(... paused: false))`.
- **H1** — `TempoNow`'s `BreathingAura` (60→30fps), `RotatingArc` (30→24fps), `ShimmerOverlay` (now skips its plusLighter pass when invisible/off + honors Reduce Motion), and `PulseRing` all moved to gated `AmbientTimeline`, threaded with a `isVisible` flag driven by Today's scroll offset. Both imperceptible `±0.6%` `.breathing()` loops removed.
- **H2** — `WatcherIcon` gated; gained an optional injected `rotation:`/`angle(_:)` so a row of radars can share one clock.
- **H3** — deleted the two unused whole-table `@Query` (`allProposals`, `allSignals`) from `TodayView`.
- **H4** — added `.cardElevation()` (one shadow, no blend mode); switched `BriefTeaserCard`, `ChapterCardCompact`, `WatcherCardSection`, and `TempoNow`'s lift off the 3-shadow + plusLighter Material A.
- **H5** — `FloatingGlyph` resolves its cropped icon once via `.task` off-main instead of decoding/cropping every frame; `IconCropping` cache is now a bounded, thread-safe `NSCache` keyed by full data identity.
- **CompassDial** — static rings/ticks hoisted out of the per-frame closure; 30→12fps; gated.
- **Formatters** — `AtlasFormat.clockHMS` static for `LiveClock`; `AtlasFormat.relative` no longer allocates per call; `Constellation.shortDueLabel` reuses the cached static.

**Still outstanding** (not in this pass): H6 (un-predicated `FetchDescriptor` / `CaptureSheet` 1Hz poll), all Mediums (the `TempoNow` `.periodic(1s)` whole-tree rebuild, connector per-signal fan-out, `Typewriter` cancellation, per-event saves), and all Lows (`#Index`, `URLSession` timeouts, Anthropic prompt caching, etc.).

---

## Critical & High — fix now

### H1. Collapse + gate the always-on animation loops on Today
**Files:** `TempoNow.swift:18,336,390,419,453,486`, `TodayView.swift:32-56,88-92`, `WatcherIcon.swift:11`, `LiveClock.swift:30` (CompassDial), `Constellation.swift:428`
**Why it hurts:** `TempoNow.body` wraps the whole header/hero/rail in `TimelineView(.periodic(by:1.0))` and inside it stacks `BreathingAura` (1/60, two RadialGradients), `RotatingArc` (1/30), `ShimmerOverlay` (1/30, `.blendMode(.plusLighter)` masked to text), `PulseRing` (1/30), and `BreathingScale` (1/30) — every one hardcoded `paused: false`. Layer that on `CompassDial` (1/30), up to 6 `WatcherIcon` radars (each 1/30), and two `.breathing()` text scalers (date header + hero title at ±0.6%, imperceptible). Because Today is a plain `VStack` in a `ScrollView` (not lazy), every loop keeps firing at 30–60fps even after it scrolls out of the viewport — SwiftUI only suspends `.animation` timelines when the whole *scene* backgrounds, not when a subview leaves the visible bounds. This is continuous GPU/CoreAnimation wakeup load while the user is simply reading. Gradients + `.plusLighter` force offscreen compositing passes every frame.

**Fix:** Three moves.

1. **One clock, not five.** Drive all of `TempoNow`'s decorative phases from a single 30fps timeline and pass plain phase values into child layers:
```swift
// before: five nested TimelineView(.animation(...)) each with paused:false
// after: one ambient timeline computes all phases, children get plain modifiers
TimelineView(.animation(minimumInterval: 1/30, paused: !isVisible || phase != .active || reduceMotion)) { ctx in
    let t = ctx.date.timeIntervalSinceReferenceDate
    heroLayers(aura: auraScale(t), arc: arcAngle(t),
               shimmer: shimmerOpacity(t), pulse: pulseRadius(t))
}
```

2. **Gate `paused:` on real visibility + scene + motion**, never a literal `false`. `TempoNow` already tracks scroll via `ScrollOffsetKey` (`TodayView.swift:62`) — derive a `heroVisible` Bool and thread it down. Add to every decorative component:
```swift
@Environment(\.scenePhase) private var phase
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// paused: phase != .active || reduceMotion || !isVisible
```

3. **Match fps to motion and drop invisible work.** `BreathingAura` 1/60 → 1/30 (a 3.4s breathe is imperceptible above 30fps). `CompassDial`'s 48s drift needs ~8–12fps, not 30. `ShimmerOverlay` returns opacity 0 for ~40% of its 6.5s cycle yet still composites the masked plusLighter gradient — short-circuit to `Color.clear` when opacity is 0. Drop the date-header `.breathing()` entirely (±0.6% scale is below visible threshold). For purely periodic pulses (`PulseRing`, `BreathingScale`), prefer a declarative `.repeatForever(autoreverses:)` on one `@State` driver — the render server runs those without re-running a Swift closure per frame.

**Future-proofing:** Introduce one approved wrapper, e.g. `AmbientTimeline { ctx in … }`, that internally injects `scenePhase + reduceMotion + isLowPowerMode (ProcessInfo.processInfo.isLowPowerModeEnabled)` and a configurable fps. Ban raw `TimelineView(.animation(` with a CI grep that fails on the literal `paused: false`. Convention: ≤1 decorative `.animation` timeline per logical component; any glyph rendered in a `ForEach` (radar, compass) takes an injected phase, never its own timeline.

### H2. `WatcherIcon` instantiates an independent 30fps loop per row — up to 6 on one Today section
**File:** `WatcherIcon.swift:11`, `TodayView.swift:460-485` (header icon + `ForEach(watchers.prefix(5))`), also `AtlasNoticedCard.swift:18`, `BriefSections.swift:360`
**Why it hurts:** The sweep arm is a pure function of time and identical across instances, yet each icon owns its own `TimelineView(.animation(1/30))` redrawing a gradient sweep `Rectangle` — SwiftUI schedules N separate per-frame closures for one tiny 11–12pt decorative radar.
**Fix:** Make `WatcherIcon` take an injected rotation `phase` from a single parent/ambient timeline so all radars share one clock; or render row icons as a static frame and animate only the header. Folds N timelines into one computation.
**Future-proofing:** Code review flags any `TimelineView` inside a view used in a `ForEach`.

### H3. Two unused whole-table `@Query` on the launch screen
**File:** `TodayView.swift:11-12`
```swift
@Query private var allProposals: [Proposal]
@Query private var allSignals: [Signal]   // neither identifier referenced anywhere in the file
```
**Why it hurts:** Today is the launch/most-visited screen. Each runs an unbounded `FetchDescriptor` (no predicate/limit) pulling every `Proposal`/`Signal` row — including blob columns (`proposedPayloadJSON`, `optionsJSON`, `rawDataJSON`) — into hydrated models, **and registers an observer**. The connector loop writes a batch of Signals every 15 min and `signal_received` handlers mutate `signal.processed`; Signals are the fastest-growing table. So every agent write invalidates `TodayView` and refetches a whole table **for data that is never displayed**.
**Fix:** Delete both lines. If a count is ever needed, use `fetchCount` with a predicate, never a standing whole-table `@Query`.
**Future-proofing:** Custom lint rule: a stored `@Query` property whose name never reappears in the file is an error. Every `@Query` gets a predicate + `fetchLimit`.

### H4. Material A regression — 3 stacked shadows + plusLighter overlay on every card, repeated in non-lazy scroll rows
**File:** `Theme.swift:147-200` (RakingShadow = three `.shadow()` + `TopHighlight` `.blendMode(.plusLighter)`); call sites `TodayView.swift:177,366-371,455,558`, `TempoNow.swift:126-130`, `ChaptersListView.swift:204`, `BriefSections.swift:379`, `SettingsView.swift:171,296,421,531`, `Constellation.swift:72`, `CaptureSheet.swift:123`
**Why it hurts:** The diff replaced a near-free single 1px stroke with `MaterialA` = three blurred shadow passes + an offscreen plusLighter compositing pass per card. On Today these cards live in a **non-lazy** `VStack`/`ScrollView` (`TodayView.swift:32-54`), so all are realized at once and re-rasterized during scroll — exactly when GPU budget is tightest. `BriefTeaserCard` rows (`TodayView.swift:455`) multiply this by N in a `ForEach`. Worst: `TempoNow` swapped its hairline border for `.materialLift()` (`TempoNow.swift:126-130`) on a container whose interior is invalidated by five animation loops, recompositing the shadow+blend layer alongside them.
**Fix:** Collapse RakingShadow to **one** `.shadow()` (≈95% of the look at 1/3 the cost) and drop/replace the plusLighter `TopHighlight` with a plain low-alpha hairline. Add a lightweight `.cardElevation()` token (single shadow, no blend mode) for list/scroll rows; reserve full Material A for the single hero card per screen. Give `TempoNow` its old hairline back (it doesn't need 3 shadows while it's animating). Consider `LazyVStack` for `briefsForTodaySection` if brief count grows.
**Future-proofing:** Rule documented in `DESIGN_LANGUAGE.md`: blend modes and multi-shadow stacks are **hero-only**, forbidden in repeated/scrolled rows. Never stack >1 `.shadow()` on a view inside a `ForEach`/scroll container, and never put a multi-shadow/blend-mode modifier on the same level as a `TimelineView(.animation)`.

### H5. Image decode + full-image pixel-scan crop runs on `@MainActor` and inside `body`
**Files:** `IconGenerator.swift:14-55` (`@MainActor` pipeline), `IconCropping.swift:11-22` (unbounded static cache), `Constellation.swift:428-448` (cropped() in a 30fps timeline body), `RibbonHeader.swift:46`
**Why it hurts:** `IconGenerator.regenerate`/`generateMissing` are `@MainActor`, so post-`await` work — `Data(base64Encoded:)` of a ~1MB PNG, `UIImage(data:)`, `croppedToContent()` (full 1024px pixel scan), `pngData()` re-encode — resumes **on the main thread**. `SettingsView.generateAll()` loops 20+ chapters; `RootView.task` does the same on launch → single-digit-to-tens-of-ms main-thread hitches per completion. Separately, `FloatingGlyph` calls `IconCropping.cropped(data)` **inside its 1/30 timeline closure** (`Constellation.swift:443`): every frame hashes 16 bytes + dictionary-looks-up + re-wraps a `UIImage` (~120 ops/sec for 4 glyphs), and on a cache miss runs the full decode+pixel-scan synchronously mid-animation. The cache itself (`[Int:UIImage]`, key `count.hashValue ^ prefix(16).hashValue`) is unbounded, never evicted (decoded 1024px bitmaps ~MB each → slow memory leak / jetsam risk), collision-prone, and mutated from the render path with no isolation.
**Fix:**
```swift
// Constellation FloatingGlyph — resolve ONCE, not per frame:
@State private var croppedImage: UIImage?
// .task(id: iconData) { croppedImage = await Task.detached { iconData.flatMap(IconCropping.cropped) }.value }
TimelineView(.animation(1/30, paused: paused)) { ctx in
    if let img = croppedImage { Image(uiImage: img).offset(offset(ctx.date)) } // closure only applies offset
}
```
Drop `@MainActor` from `regenerate`/`generateMissing`/`croppedPNGData`; do network + base64 + crop + encode on a background executor and hop to MainActor only for the SwiftData `iconData` write. Replace the static dictionary with `NSCache<NSData, UIImage>` (auto-evicts, thread-safe), keyed on full data identity. Since `IconGenerator` already stores pre-cropped PNGs, at render time just do `UIImage(data:)` — never `croppedToContent()` in `body`.
**Future-proofing:** Rule: `body` and `TimelineView`/`Canvas` closures are allocation- and compute-free — no image decode, no pixel scans, no formatter construction, no dictionary-cache lookups. Lint `UIImage(data:)`/`pngData()`/`cropped(`/`croppedToContent` inside `var body` or `@MainActor` members. Any process-lifetime image cache must be `NSCache`.

### H6. Whole-table fetches + N+1 relationship faulting in agent tools and capture
**Files:** `AgentTools.swift:249-257` (`PersonLookupTool`), `CaptureHandler.swift:94`, `CaptureSheet.swift:215-226`
**Why it hurts:** `PersonLookupTool` does `try ctx.fetch(FetchDescriptor<Chapter>())` (no limit), then per chapter faults `c.decisions` and `c.entries` and substring-scans in Swift — an unbounded N+1, run per agent turn (capture/signal/watcher/daily-scan). `CaptureHandler` fetches the whole `Chapter` table just to `.first(where: id ==)`. `CaptureSheet`'s poll loop fetches the **entire `AppEvent` table every second** for up to 90s on the **main-actor** context, linear-scanning for one id — directly competing with the "thinking" spinner the user is staring at (AppEvents only GC after 30 days, so this grows unbounded).
**Fix:** Find-by-id is always predicate + `fetchLimit(1)`:
```swift
var d = FetchDescriptor<AppEvent>(predicate: #Predicate { $0.id == eventID })
d.fetchLimit = 1
let evt = try? context.fetch(d).first
```
Better, replace the `CaptureSheet` 1Hz poll with an event-driven completion (a continuation/`NotificationCenter` keyed by event id) so the sheet awaits a signal instead of polling. For `PersonLookupTool`, push the text match into a `#Predicate` on `Decision`/`Entry` directly and add `fetchLimit`.
**Future-proofing:** Ban un-predicated `FetchDescriptor<T>()` in UI code. Convention: find-one = predicate + `fetchLimit(1)`; text search = predicate on the leaf model, never per-parent relationship faulting in a loop. Prefer event-driven completion over fixed-interval polling.

---

## Medium — fix soon

- **`TempoNow` wraps the whole tree in `.periodic(by:1.0)`** (`TempoNow.swift:17-34`): once/sec it re-runs `resolveFocus()` (3 linear scans), rebuilds the hero card, and rebuilds the rail's `GeometryReader` (ForEach over events + 19 hour ticks + `Array(todoHours.enumerated())` reallocated each tick). Only the seconds label + cursor need 1Hz — scope the timeline to those two `Text`/dot views; hoist everything else out and precompute the tick `Range` as a stored `let`.
- **`AtlasFormat.relative()` allocates a `RelativeDateTimeFormatter` per call** (`Formatters.swift:50-54`), inside `ChapterCardFull` row bodies (`ChaptersListView.swift:195`) → N allocations per render, the outlier among otherwise-cached `AtlasFormat` statics. Make it a `static let`.
- **`LiveClock` allocates a `DateFormatter` every second** (`LiveClock.swift:15-19`) in the app-lifetime header; same per-render pattern in `Constellation.shortDueLabel` (`:386`) and `EngineStatus.lastTickLabel` (`SettingsView.swift:446`). Hoist to `static let` or use `Text(date, format: .dateTime…)` (SwiftUI caches the formatter).
- **`CompassDial` 30fps for a 48s drift** (`LiveClock.swift:30-37`): drop to 1/12–1/8 and rotate only the needle `ZStack`, hoisting the static rings/ticks/label out of the closure.
- **Gemini image pipeline serial + unpaced on launch** (`IconGenerator.swift:20-25`): `generateMissing` fires back-to-back requests (no `Task.sleep`, unlike `generateAll`'s 7s spacing at `SettingsView.swift:338`), tripping 429s → exponential backoff (8/18/32s) while holding `@MainActor` on the launch path. Defer off launch, pace via one shared limiter, run off-main.
- **Connector fan-out = one full LLM run per signal** (`EventHandlers.swift:373-393`, `SignalReceivedHandler` `:275-310`): N new signals → N independent multi-second `AtlasLLM.run` calls serialized on the actor. Coalesce into one "triage these 12 signals" run and/or a cheap local pre-filter; add a per-day agent-run budget.
- **Connector dedupe fetches full Signal rows (incl. `rawDataJSON` blob) every 15 min** (`EventHandlers.swift:373-378`) just to build a `Set` of `externalId`. Use `propertiesToFetch: [\.externalId]` or predicate-fetch the candidate ids with `fetchLimit`.
- **`Typewriter` recursive `asyncAfter` with no cancellation** (`Typewriter.swift:24-44`): ~90 main-queue blocks/sec, no `.onDisappear` stop, and `restart()` on text change spawns a *second* parallel chain racing the same counter. Switch to a cancellable `Task { … sleep }` loop cancelled in `.onDisappear` / at `restart()` top, or a generation-counter guard.
- **`drainPendingEvents` saves up to 3× per event in the loop** (`AtlasAgent.swift:138-155`) plus each `create_*` tool saves independently (`AgentTools.swift:447,504,583,630`) → a dozen+ WAL-flushing transactions per 30s tick. Keep the `.processing` save (crash recovery) but let tools insert without saving and save once at the end of the handler turn.
- **Big `Data` columns stored inline, decoded synchronously** (`Chapter.swift:16-22` iconData; `Brief.structureData` decoded in `BriefRenderer`'s computed `structure` per render): decode `structureData` once into `@State` via `.task`; for icons use an out-of-row file or an `iconVersion: Int` counter so `@Query` can still observe without inlining PNGs.

---

## Low / watch

- **No `#Index` on any model** (`Event.swift:6-26` et al.): hot predicates (`statusRaw`, `sourceRaw`, `arrivedAt`, `nextCheck`, `id`) are full scans. Cheap now; add `#Index` on `AppEvent([\.statusRaw],[\.typeRaw],[\.createdAt])`, `Watcher([\.statusRaw,\.nextCheck])`, `Signal([\.sourceRaw,\.arrivedAt],[\.externalId])`, `Brief/Proposal([\.statusRaw])` before tables grow.
- **`SettingsView` holds 3 unbounded `@Query` filtered in Swift on a 30s timer** (`SettingsView.swift:7-9`); **`MorningView` holds a whole-`Chapter` `@Query` used only at Send-time** (`:15`); **`DecisionsTab` fetches all pending decision proposals app-wide then filters by chapter in Swift** (`:11-17`) — replace count uses with `fetchCount(predicate:)`, standing-query-only-used-in-action with a one-shot fetch, and add a `chapterID` scalar for predicate-side scoping.
- **`TodayView` derives `allTodos` (flatMap over faulted `todos` + sort) 3× per body** (`:203-241,232-242`); `MorningView.countsText` rescans all sentences twice (`:31-52`) — compute each derived collection once into a local `let`.
- **`RootView`/`SettingsView`/`Constellation` `Timer` on `.common` runloop mode** (`RootView.swift:95-97`, `SettingsView.swift:53-55`, `Constellation.swift:394`): can fire mid-scroll; `clockTick &+= 1` invalidates the *whole* RootView body every 60s. Use `.default` mode and scope the ticking `@State` to the smallest leaf.
- **`RootView` animates `.blur(radius:8)` over the full live tree when Capture opens** (`:78-80`): full-screen Gaussian blur over still-ticking animations. Pause ambient motion while `showCapture`, or use the sheet's `presentationBackground` material.
- **LLM calls use `URLSession.shared` with no per-request timeout** (`ClaudeClient.swift:117-125`, `GeminiAgent.swift:148-155`, `GeminiClient.swift:75-95`); the 180s budget is only checked *between* iterations, so a hung socket isn't torn down. Add a shared `AtlasURLSession` with `timeoutIntervalForRequest`/`ForResource` and wrap `sendOnce` in a real cancellable timeout.
- **`ISO8601DateFormatter()`/`DateFormatter()` per row in agent tool loops** (`AgentTools.swift:152,159,164,210,683`; `Proposal.materialize` `:126`): a 50-todo chapter builds 50 formatters per `chapter_details` call. Use the existing `AtlasFormat.iso` static (`AgentTools.swift:674`) everywhere.
- **Foreground 30s loop + BGAppRefresh can overlap; each `tickOnce` builds a throwaway `ModelContext`** (`BackgroundRefresh.swift:42-50`, `AtlasAgent.swift:73-94,116-122`): add an `isTicking` re-entrancy guard, reuse one long-lived background context, and early-out on a zero-pending count before a full fetch.
- **`ConstellationView` re-tessellates all edge beziers + curved labels on every drag frame** (`:127-160,471-512`): show straight unlabeled edges during an active drag, restore curved labels on `.onEnded`. Cache bezier sample tables keyed on the control-point triple.
- **`Constellation` long-press `Timer` not invalidated on disappear** (`:392-401`) — add `.onDisappear { cancelPress() }` or use a `LongPressGesture`.
- **`SeedV2` dispatched unconditionally every launch** (`AppContainer.swift:35-43`), pays a main-thread `Chapter` fetch even on the 100th launch — gate behind a persisted `didSeedV2` flag.
- **`ClaudeClient` rebuilds + re-serializes the full request body (system prompt + tool decls) every loop iteration** (`:48-63,109`) with no Anthropic prompt caching — hoist the immutable prefix out of the loop and add `cache_control` on the system/tools blocks.
- **Confirmed-clean refactors (do not re-flag):** `Proposal.materialize` dedup (`ReviewQueueView.swift:147-160`) and the provider-neutral `LLMClient.swift:8-142` hoist are perf-positive — only follow-up is the shared-formatter note above.

---

## Performance playbook — keep it fast going forward

Copy-pasteable conventions specific to this codebase:

1. **One ambient frame driver, never N.** Add `AmbientTimeline { ctx in … }` as the *only* sanctioned looping-animation primitive. It injects `scenePhase`, `accessibilityReduceMotion`, and `ProcessInfo.processInfo.isLowPowerModeEnabled`, freezes when any says so, and exposes a configurable fps. Components rendered in a `ForEach` take an injected `phase`, never their own `TimelineView`.
2. **`paused:` must reference a visibility/scene source — never a literal `false`.** CI grep that fails on `paused: false` and on raw `TimelineView(.animation(` outside `AmbientTimeline`.
3. **Match fps to motion.** Multi-second cycles / <5°·s⁻¹ motion → 8–12fps. Reserve 30–60fps for fast translation/shimmer only. Breathing amplitudes <1% should be `.repeatForever` on a `@State` scale (render-server driven), not a per-frame timeline.
4. **A `TimelineView` closure contains only views whose pixels change at that cadence.** Hoist static structure (titles, ticks, glyph rows, shadows) above the closure. Wrapping a whole card/section in a timeline is a code smell.
5. **`body` and animation closures are allocation- and compute-free.** No `DateFormatter()`/`ISO8601DateFormatter()`/`RelativeDateTimeFormatter()` construction, no `UIImage(data:)`/`croppedToContent()`/pixel scans, no dictionary-cache lookups, no JSON decode. Pre-resolve into `@State` via `.task`. Lint: any of those tokens inside `var body` or an animation closure fails review.
6. **All formatters are `static let` in `AtlasFormat`.** Zero formatter constructions in `Views/` or tool loops. `grep -rn 'DateFormatter()\|ISO8601DateFormatter()\|RelativeDateTimeFormatter()\|NumberFormatter()' Views/ Agent/` must return nothing outside `AtlasFormat`.
7. **`@Query` discipline:** every stored `@Query` is referenced in `body`, carries a `#Predicate` + `fetchLimit`, and excludes blob columns where possible. Counts/aggregates use `fetchCount(predicate:)`, never a whole-table query filtered in Swift. Find-one is always `#Predicate { $0.id == … }` + `fetchLimit(1)`. Custom lint: a stored `@Query` whose name never reappears in the file is an error.
8. **Image and JSON work runs off `@MainActor`.** Decode/crop/encode on a background executor (`Task.detached`); marshal only the resulting `Data`/`UIImage` back to the actor owning the `ModelContext`. Image caches are `NSCache` with `countLimit`/`totalCostLimit`, never a raw `static var [_:UIImage]`. Lint `pngData()`/`UIImage(data:)`/`cgImage` inside `@MainActor` members.
9. **Elevation budget:** `materialA` = 3 shadows + plusLighter (offscreen passes). Rows inside any `ForEach`/scroll use `.cardElevation()` (one shadow, no blend mode); full Material A and any blend mode are hero-only, documented in `DESIGN_LANGUAGE.md`. Never put a multi-shadow/blend-mode modifier at the same level as a `TimelineView(.animation)`.
10. **Periodic workers:** actor-hosted loops reuse one `ModelContext`, guard re-entrancy (`if isTicking { return }`), early-out on a zero-work count before a full fetch, and check `Task.isCancelled` immediately after `sleep`. UI heartbeat timers use `.default` runloop mode (not `.common`) and live in the smallest leaf, never a top-level container. Every stored `Timer` has a matching `.onDisappear` invalidation; prefer `Task { … sleep }` loops (cancellation is free) and SwiftUI gestures over manual timers.
11. **Fan-out → batch.** One agent run per batch of signals, not per signal, gated behind a cheap local heuristic and a per-day run budget. One shared `AtlasURLSession` with explicit timeouts (no `URLSession.shared`); every wall-clock budget paired with real `Task` cancellation. Build the immutable LLM request prefix once and enable prompt caching from day one.

**PR perf checklist (paste into the template):** ☐ no new `TimelineView(.animation(` with `paused: false` ☐ no formatter/`UIImage(data:)`/JSON decode in `body` ☐ every `@Query` predicate+limit and referenced in `body` ☐ find-one uses `fetchLimit(1)` ☐ image/JSON work off `@MainActor` ☐ rows in `ForEach` use single-shadow elevation ☐ new `Timer` has `.onDisappear` and `.default` mode ☐ new model fields >1KB are externalStorage; predicate fields have `#Index`.

---

## How to actually measure (no Xcode on this box → do it on a dev Mac + device)

Profile on a **real device** (Release config), not Simulator — GPU/compositing and energy numbers are meaningless on Simulator.

- **Animation Hitches** template → confirm H1/H2/H4. Sit on Today doing nothing, then scroll. Healthy: near-zero hitches and the GPU/CoreAnimation track idles to ~0% when you stop touching the screen. Today as-is will show continuous GPU activity at rest — that's the smoking gun. Re-run after gating: at-rest GPU should drop to baseline.
- **Xcode → Debug → "Color Changes" / "Flash updated regions"** (and **Color Offscreen-Rendered** / **Color Blended Layers**): with the app idle on Today, *nothing* should flash if animations are properly paused; today the hero, radars, compass, and breathing text will strobe every frame. "Color Offscreen-Rendered Yellow" highlights the `.plusLighter` masks and multi-shadow cards (H4/H5) — they should turn from yellow toward not-yellow after collapsing shadows/blends.
- **Time Profiler** → confirm H5/H6 and the formatter findings. Capture during (a) launch, (b) `generateAll`, (c) Capture-sheet "thinking", (d) Chapters scroll. Look for main-thread frames in `croppedToContent`, `UIImage(data:)`, `DateFormatter`/`RelativeDateTimeFormatter` init, and `SwiftData fetch`. Healthy: those symbols don't appear on the main thread; image/crop frames live on a background queue.
- **SwiftUI instrument (Instruments SwiftUI lane) + `Self._printChanges()`** in `TodayView.body` and `TempoNow.body` → confirm H1/H3 and the `.periodic(1s)` finding. Healthy: `TodayView.body` does **not** re-run on every background-agent write (proves H3 fixed) and `TempoNow` body re-evaluates only the seconds label, not the hero/rail, each second. The lane's "View Body" durations on Today should be short and infrequent at rest.
- **Allocations / Leaks** → confirm H5's unbounded `IconCropping.cache`. Mark a generation, run "Reset & regenerate all" icons several times, mark again. Healthy with `NSCache`: persistent `UIImage` bytes plateau and drop under a simulated memory warning (Instruments → Simulate Memory Warning); today's static dictionary will grow monotonically and survive the warning.
- **Energy Log** (device, untethered via Instruments wireless or Settings → Developer → Logging) → confirm the overall battery thesis. Leave Today foregrounded and idle for a few minutes. Healthy: CPU/GPU energy "Low"/"idle" at rest; today it should read elevated continuously. Re-check with Low Power Mode on (decorative motion should fully freeze after the playbook changes) and with Reduce Motion enabled.

For each top finding, the pass/fail is the same shape: **at rest, the GPU and main thread should go quiet.** If they don't, an animation loop or a `body` is doing work it shouldn't.
</content>
</invoke>
