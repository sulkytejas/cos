import Foundation
import SwiftData
import os

/// AtlasAgent — the in-app worker the v0.2 brief specified. Runs an event
/// loop while the app is foreground (and via BGTaskScheduler in the
/// background), draining the `AppEvent` queue, polling watchers + connectors,
/// and writing Briefs / Proposals back through SwiftData.
///
/// Unlike the original brief's Node worker, this lives in the iOS app — same
/// data, same agent loop, same tools, just hosted inside the app process so
/// we don't need a server.
actor AtlasAgent {
    static let shared = AtlasAgent()

    private let log = Logger(subsystem: "com.atlas.app", category: "AtlasAgent")
    private var container: ModelContainer?
    private var loopTask: Task<Void, Never>?
    private(set) var lastTickAt: Date?
    private(set) var lastError: String?
    private(set) var pendingEventCount: Int = 0
    private(set) var lastWatcherCheckAt: Date?
    private(set) var lastConnectorPollAt: Date?
    /// Stamp of the most-recent dailyScan we enqueued (`"YYYY-M-D"`). Avoids
    /// re-fetching the whole AppEvent table on every 6am tick.
    private var lastDailyScanStamp: String?
    /// Tick counter so we GC done events on a slow cadence (every ~50 ticks =
    /// ~25 minutes of foreground time).
    private var tickCounter: Int = 0

    func attach(container: ModelContainer) {
        self.container = container
        // Stuck-event recovery: if the app crashed mid-handler last run, any
        // AppEvent left in `.processing` will otherwise be orphaned. Reset
        // them to `.pending` so the next drain picks them up.
        recoverStuckEvents()
    }

    private func recoverStuckEvents() {
        guard let container else { return }
        let ctx = ModelContext(container)
        let processingRaw = EventStatus.processing.rawValue
        let stuck = (try? ctx.fetch(FetchDescriptor<AppEvent>(
            predicate: #Predicate { $0.statusRaw == processingRaw }
        ))) ?? []
        for evt in stuck {
            evt.status = .pending
            evt.error = "recovered from .processing on launch"
        }
        if !stuck.isEmpty {
            try? ctx.save()
            log.info("recovered \(stuck.count) stuck events")
        }
    }

    /// Start the foreground loop. Idempotent — calling twice is a no-op.
    func startForegroundLoop() {
        guard loopTask == nil else { return }
        log.info("starting foreground loop")
        loopTask = Task { [weak self] in
            await self?.runLoopUntilCancelled()
        }
    }

    func stopForegroundLoop() {
        loopTask?.cancel()
        loopTask = nil
        log.info("stopped foreground loop")
    }

    /// One agent pass — event drain + watcher check + connector poll.
    /// Used by both the foreground loop and the background refresh task.
    func tickOnce() async {
        guard let container else {
            log.error("tickOnce: no container attached")
            return
        }
        lastTickAt = Date()
        tickCounter &+= 1
        do {
            let workCtx = ModelContext(container)
            try await drainPendingEvents(in: workCtx)
            try await checkDueWatchers(in: workCtx)
            try await maybePollConnectors(in: workCtx)
            try await maybeRunTimeTriggers(in: workCtx)
            if tickCounter % 50 == 0 {
                gcOldEvents(in: workCtx)
            }
            lastError = nil
        } catch {
            lastError = String(describing: error)
            log.error("tick failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sweep done/failed events older than 30 days. Runs on a slow cadence.
    private func gcOldEvents(in ctx: ModelContext) {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let doneRaw = EventStatus.done.rawValue
        let failedRaw = EventStatus.failed.rawValue
        let old = (try? ctx.fetch(FetchDescriptor<AppEvent>(
            predicate: #Predicate {
                ($0.statusRaw == doneRaw || $0.statusRaw == failedRaw)
                    && $0.createdAt < cutoff
            }
        ))) ?? []
        for evt in old { ctx.delete(evt) }
        if !old.isEmpty {
            try? ctx.save()
            log.info("gc'd \(old.count) old events")
        }
    }

    // MARK: - Foreground loop

    private func runLoopUntilCancelled() async {
        while !Task.isCancelled {
            await tickOnce()
            // Sleep 30s between passes — same cadence as the v0.2 worker spec.
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
    }

    // MARK: - Pending event drain

    private func drainPendingEvents(in ctx: ModelContext) async throws {
        let pendingRaw = EventStatus.pending.rawValue
        var descriptor = FetchDescriptor<AppEvent>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 6   // soft cap per tick
        let pending = try ctx.fetch(descriptor)
        pendingEventCount = (try? ctx.fetchCount(
            FetchDescriptor<AppEvent>(predicate: #Predicate { $0.statusRaw == pendingRaw })
        )) ?? pending.count

        for event in pending {
            event.status = .processing
            do { try ctx.save() } catch { log.error("save .processing failed: \(error.localizedDescription, privacy: .public)") }
            do {
                try await EventDispatcher.handle(event: event, ctx: ctx, agent: self)
                event.status = .done
                event.processedAt = Date()
                event.error = nil
            } catch {
                event.status = .failed
                event.processedAt = Date()
                event.error = String(describing: error)
                log.error("event \(event.id.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            // Final-status save: throw on failure so the outer tick catches it
            // and surfaces in lastError. Better than silent loss of done/failed.
            try ctx.save()
        }
    }

    // MARK: - Watcher cadence

    private func checkDueWatchers(in ctx: ModelContext) async throws {
        let activeRaw = WatcherStatus.active.rawValue
        let now = Date()
        let due = try ctx.fetch(FetchDescriptor<Watcher>(
            predicate: #Predicate { $0.statusRaw == activeRaw && $0.nextCheck <= now }
        ))
        lastWatcherCheckAt = now
        for watcher in due {
            // Enqueue a watcher_due event instead of doing the work inline —
            // keeps the loop uniform (everything flows through events).
            // We only advance nextCheck here (so the watcher doesn't refire
            // every tick); lastChecked is set by WatcherDueHandler on success.
            let payload = WatcherDuePayload(watcherID: watcher.id)
            ctx.insert(AppEvent(type: .watcherDue, payload: payload))
            watcher.nextCheck = now.addingTimeInterval(TimeInterval(watcher.cadenceMinutes * 60))
        }
        if !due.isEmpty { try? ctx.save() }
    }

    // MARK: - Connector cadence

    private func maybePollConnectors(in ctx: ModelContext) async throws {
        let now = Date()
        if let last = lastConnectorPollAt, now.timeIntervalSince(last) < 15 * 60 {
            return
        }
        lastConnectorPollAt = now
        ConnectorRunner.pollOnce(in: ctx)
    }

    // MARK: - Time triggers (daily scan, weekly drift)

    private func maybeRunTimeTriggers(in ctx: ModelContext) async throws {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .weekday], from: now)
        guard let hour = comps.hour, hour == 6 else { return }

        let stamp = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        // Fast path — if we enqueued today's scan during this app session,
        // skip without hitting SwiftData at all. Cheap idempotency.
        if lastDailyScanStamp == stamp { return }

        // Slow path on the first 6am tick after launch: confirm via DB so a
        // restart inside the 6am window doesn't double-enqueue.
        let dailyRaw = EventType.dailyScan.rawValue
        let existing = try ctx.fetch(FetchDescriptor<AppEvent>(
            predicate: #Predicate { $0.typeRaw == dailyRaw }
        ))
        let already = existing.contains {
            (try? JSONDecoder().decode(DailyScanPayload.self, from: $0.payloadJSON))?.dayStamp == stamp
        }
        if !already {
            ctx.insert(AppEvent(type: .dailyScan, payload: DailyScanPayload(
                dayStamp: stamp,
                forwardDrift: (comps.weekday == 1)   // Sunday in IST
            )))
            try? ctx.save()
        }
        lastDailyScanStamp = stamp
    }
}

// MARK: - Event payloads

struct CapturePayload: Codable {
    let text: String
    let kind: String        // "todo" / "decision" / "journal" / "auto"
    let chapterID: UUID?
}

struct WatcherDuePayload: Codable {
    let watcherID: UUID
}

struct ChapterCreatedPayload: Codable {
    let chapterID: UUID
}

struct SignalReceivedPayload: Codable {
    let signalID: UUID
}

struct DailyScanPayload: Codable {
    let dayStamp: String
    let forwardDrift: Bool
}

struct BriefActedOnPayload: Codable {
    let briefID: UUID
    let action: String      // "primary" / "snooze" / "dismiss" / "dig_deeper"
}

// MARK: - System prompt

/// The Atlas system prompt — instilled with the 8 principles, a strict
/// guide to which UI components the agent may compose, and example briefs
/// covering the four shapes (meeting, trip, deadline, creative project).
enum AtlasSystemPrompt {
    static let text: String = """
    You are Ayumi, a calm and considered chief-of-staff for the user. You read,
    research, synthesize, and propose — you never act on the world. You only
    write to your own database (briefs, proposals, watchers). The user is
    always in the loop for anything that touches money, identity, or
    relationships.

    # The eight principles

    1. **Atlas prepares, never acts.** Never send emails, never call APIs that
       transact, never schedule a thing — only propose.
    2. **The Brief is the unit of value.** When you recognize a situation,
       compose a Brief — a small preparation document a chief of staff would
       leave on the desk.
    3. **Preparation is dynamic, not modular.** There is no "meeting prep
       feature" vs "trip prep feature." You reason about the situation and
       compose a Brief that fits it.
    4. **Input is passive-first, residual second.** Most of what fills Atlas
       comes from signals (Gmail, Calendar, Drive). The user types only what
       you couldn't know.
    5. **The UI composes from a library, dynamically.** Briefs are JSON
       structures referencing components from a fixed library. You never
       invent components.
    6. **The database is your memory.** Read prior briefs, decisions, todos,
       journal entries before composing — your output should be informed by
       them.
    7. **Async and event-driven.** Each event you process is independent.
       Don't depend on conversational state.
    8. **Cognitive offload is the product.** A line like "Handled 23 newsletters
       overnight" is not decoration — it's why the user trusts you.

    # Microcopy & tone

    Never exclaim. Never write "Great job" or anything performative. Numbers,
    dates, and times go in monospace (the renderer handles font choice — your
    job is to keep prose short and exact). Refer to yourself sparingly:
    "Atlas noticed" or "I drafted" — not "I'll happily help." Serif italic is
    for emphasis; never bold.

    # The component library

    A Brief structure is `{ "sections": [...] }`. Each section is
    `{ "kind": "<name>", "data": {...} }`. The valid kinds and their data
    shapes are:

    - `person` — `{ name, role, avatar (1-2 letters), facts: [string],
       mutual?: [{name, via}] }`
    - `timeline` — `{ title, items: [{ date, text, subtle?: bool }] }`
    - `prediction` — `{ title, items: [{ text, confidence: "high"|"medium"|"low" }] }`
    - `materials` — `{ title, items: [{ text, ready: bool }] }`
    - `options` — `{ title, items: [{ label, reasoning, mark?: "recommended" }] }`
    - `tactical` — `{ text }` — one calm sentence with operational guidance
    - `quote` — `{ text, attribution }`
    - `watcher` — `{ text, cadence, last?: string }`
    - `diff` — `{ title, items: [{ kind: "added"|"removed"|"changed", text }] }`
    - `action` — `{ primary, secondary: [string] }`

    NEVER use a kind not in this list. If you need something else, use
    `tactical` with prose.

    # Tools

    You have tools to read state, fetch web content, and write proposals /
    briefs / watchers. Call tools to gather context before composing. Don't
    guess facts — look them up.

    Available tools:
    - `chapter_query` — list chapters (optional filter by status/type).
    - `chapter_details` — full chapter contents (todos, decisions, entries).
    - `brief_history` — prior briefs for a chapter.
    - `person_lookup` — find what's known about a person across signals.
    - `calendar_query` — calendar events from signals (date range).
    - `gmail_search` — gmail signals matching a query.
    - `web_search` — public web search (stubbed; returns plausible results).
    - `web_fetch` — fetch a URL (stubbed; returns plausible snippet).
    - `note_to_self` — leave a watcher for yourself to recheck later.
    - `create_brief` — write a Brief (the unit of value).
    - `create_proposal` — propose a todo / decision / journal entry / chapter
       (for the user to approve in the Review queue).
    - `create_watcher` — add a standing instruction.

    # Output shape

    When you have done your reasoning and made any tool calls you need, end
    by either:
    - Calling `create_brief` and/or `create_proposal` / `create_watcher`
      tools as appropriate, then
    - Returning a short plain-text summary describing what you did (this is
      logged for debugging, not shown to the user directly).

    Be terse. The user does not read your thinking. They read the Briefs and
    Proposals you write. Make those count.

    Refer to yourself as Ayumi when self-referencing in prose. Lines like
    "Ayumi noticed" or "I drafted" — never "I'll happily help."
    """
}
