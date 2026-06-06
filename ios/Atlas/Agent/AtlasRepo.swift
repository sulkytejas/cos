import Foundation
import SwiftData
import Observation
import CryptoKit
import os

/// AtlasRepo — the SINGLE SwiftData writer (SERVER_ARCHITECTURE.md §4.e).
///
/// The brain now lives on the server. iOS is a thin client: screens keep their
/// `@Query` reads verbatim and only swap imperative calls onto this repo
/// (`submitCapture / approve / dismiss / ask / actOnBrief / sync /
/// pushCalendarSignals`) in place of `context.insert(AppEvent) +
/// AtlasAgent.tickOnce()`, `Proposal.materialize`, and `AtlasLLM.complete()`.
///
/// Pattern (§4.d/§4.e):
///   - reads always serve the SwiftData cache instantly (never blank);
///   - mutations are optimistic-local, then write-through to the server, then
///     reconciled by `sync()` upserting server rows into the same `@Model`
///     tables keyed by the server `id` — which preserves `@Query` reactivity.
///   - on offline / not-configured, the optimistic local write stands and the
///     intent enqueues for a later flush via `sync()`.
///
/// `@MainActor` so it owns the main `ModelContext`; `@Observable` so screens can
/// bind to `syncState` / `lastError` for status chrome.
@MainActor
@Observable
final class AtlasRepo {
    /// Coarse connection/sync status surfaced by Settings + the Today header.
    enum SyncState: Equatable { case idle, syncing, offline, error(String) }

    private let log = Logger(subsystem: "com.atlas.app", category: "AtlasRepo")
    private let api: AtlasAPI
    private let context: ModelContext

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date?
    var lastError: String?

    init(context: ModelContext, api: AtlasAPI = .shared) {
        self.context = context
        self.api = api
    }

    // MARK: - Capture (submit → poll → read)

    /// Capture result for the screen: the proposals THIS capture produced (read
    /// off the job's `resultProposalIds`, NOT a `createdAt` window — §4.a).
    struct CaptureResult { let jobId: String; let proposalIds: [UUID] }

    /// Submit a capture. Enqueues `capture_received`, polls `event.status` to
    /// done (1s up to 90s — matching the existing CaptureScreen loop), syncs the
    /// produced proposals into the cache, and returns their ids.
    ///
    /// Offline / unconfigured: the capture can't reach the server, so we throw —
    /// the screen keeps its written draft and the user retries on reconnect.
    func submitCapture(text: String, kind: String = "auto", chapterID: UUID? = nil) async throws -> CaptureResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AtlasAPIError.badURL }

        let payload = CapturePayload(text: trimmed, kind: kind, chapterID: chapterID)
        let emit = try await api.eventEmit(type: EventType.captureReceived.rawValue, payload: payload)

        let status = try await pollJob(emit.id)
        let ids = (status?.result?.resultProposalIds ?? []).compactMap { UUID(uuidString: $0) }
        // Pull the proposals this capture produced into the cache so the result
        // turn + the Review queue render them.
        await syncProposalsQuietly()
        return CaptureResult(jobId: emit.id, proposalIds: ids)
    }

    /// Poll a job id to a terminal status (done/failed). Returns the final status
    /// row, or nil if the row vanished / timed out.
    func pollJob(_ id: String, maxSeconds: Int = 90) async throws -> EventStatusDTO? {
        for _ in 0..<maxSeconds {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return nil }
            let status = try await api.eventStatus(id)
            if let status, status.isTerminal { return status }
        }
        return try await api.eventStatus(id)   // one last read after the window
    }

    // MARK: - Ask (grounded one-shot, §4.a)

    struct AskResult { let jobId: String; let answer: String }

    /// Ask Ayumi a grounded question. Enqueues `ai.ask` (worker runs Haiku via the
    /// gateway), polls to done, returns the answer string.
    func ask(_ question: String, scope: String? = nil, history: [AskInput.AskTurn] = []) async throws -> AskResult {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AtlasAPIError.badURL }
        let job = try await api.aiAsk(AskInput(query: q, scope: scope, context: nil, history: history))
        let status = try await pollJob(job.jobId)
        if status?.status == "failed" {
            throw AtlasAPIError.server(0, status?.error ?? "Ask failed")
        }
        let answer = status?.result?.answer ?? ""
        return AskResult(jobId: job.jobId, answer: answer)
    }

    // MARK: - Review (approve / dismiss)

    /// Approve a proposal. Optimistic-local (the Review queue drains at once),
    /// then a DURABLE write-through: enqueue an `OutboxItem` so the intent
    /// survives a kill/offline, and immediately try to flush it. The server fans
    /// the payload out transition-guarded, so an at-least-once outbox replay
    /// can't double-file (§4.d). `editedPayload` is folded into the optimistic
    /// row only — the server reconstructs the canonical payload from the proposal.
    func approve(_ proposalID: UUID, chosenValue: String? = nil, editedPayload: (some Encodable)? = nil) async throws {
        optimisticallyDecide(proposalID, status: .approved)
        let id = proposalID.uuidString.lowercased()
        enqueue(.approve(id: id, chosenValue: chosenValue))
        await flushOutbox()
        // The fan-out lands in todos/decisions/entries + flips the proposal.
        await syncChaptersQuietly()
        await syncProposalsQuietly()
    }

    /// Convenience for the common no-edit approve.
    func approve(_ proposalID: UUID, chosenValue: String? = nil) async throws {
        try await approve(proposalID, chosenValue: chosenValue, editedPayload: Optional<AnyEncodableValue>.none)
    }

    /// Dismiss a proposal. Optimistic-local then durable write-through.
    func dismiss(_ proposalID: UUID) async throws {
        optimisticallyDecide(proposalID, status: .dismissed)
        let id = proposalID.uuidString.lowercased()
        enqueue(.dismiss(id: id))
        await flushOutbox()
        await syncProposalsQuietly()
    }

    // MARK: - Morning memo redline (Today agentic flow v1)

    /// Strike (or un-strike) one line of a morning turn's memo. Optimistic-local
    /// (patch the `memoJSON` line in place so Review redraws at once), then a
    /// durable write-through. Striking a `proposal`-ref line ALSO optimistically
    /// dismisses the local proposal it stands for — the server does the same when
    /// the still-pending proposal is struck, so the two reconcile to one state.
    /// Then re-pull turns + proposals so the canonical fan-out lands.
    func strikeMemoLine(turnID: UUID, lineId: String, struck: Bool) async throws {
        if let turn = fetchTurn(turnID), var memo = turn.memo,
           let idx = memo.lines.firstIndex(where: { $0.id == lineId }) {
            memo.lines[idx].struck = struck
            // Striking a proposal-ref line is a dismissal of that proposal —
            // mirror the server's side effect locally so the Review queue count
            // drops immediately and doesn't flicker back on the next pull.
            if struck, memo.lines[idx].refKind == "proposal",
               let refId = memo.lines[idx].refId, let pid = canonicalUUID(refId),
               let p = fetchProposal(pid), p.status == .pending {
                p.status = .dismissed
                p.decidedAt = Date()
            }
            turn.memo = memo
            turn.updatedAt = Date()
            saveQuietly()
        }
        let id = turnID.uuidString.lowercased()
        enqueue(.memoStrike(turnId: id, lineId: lineId, struck: struck))
        await flushOutbox()
        await deltaSyncTablesQuietly(["turns", "proposals"])
    }

    /// Keep (seal) a morning turn's memo. Optimistic-local status flip to `kept`,
    /// then a durable write-through. Idempotent (an already-kept memo is a no-op
    /// server-side). Re-pulls turns so the kept stamp reconciles.
    func keepMemo(turnID: UUID) async throws {
        if let turn = fetchTurn(turnID), var memo = turn.memo, memo.status != "kept" {
            memo.status = "kept"
            memo.keptAt = AtlasISO.string(Date())
            memo.keptBy = "user"
            turn.memo = memo
            turn.updatedAt = Date()
            saveQuietly()
        }
        let id = turnID.uuidString.lowercased()
        enqueue(.memoKeep(turnId: id))
        await flushOutbox()
        await deltaSyncTablesQuietly(["turns", "proposals"])
    }

    // MARK: - Brief actions (Start / Snooze / …)

    /// Act on a brief (Start/Snooze/Dismiss/Archive). Optimistic-local status
    /// flip, then a durable write-through (server flips status AND emits
    /// `brief_acted_on`) via the outbox so an offline action isn't lost.
    func actOnBrief(_ briefID: UUID, action: BriefAction) async throws {
        let newStatus: BriefStatus = {
            switch action {
            case .start:   return .actedOn
            case .snooze:  return .draft
            case .dismiss: return .dismissed
            case .archive: return .archived
            }
        }()
        if let brief = fetchBrief(briefID) {
            brief.status = newStatus
            saveQuietly()
        }
        let id = briefID.uuidString.lowercased()
        enqueue(.briefAct(id: id, action: action.rawValue))
        await flushOutbox()
    }

    // MARK: - Connectors (real Gmail/Calendar/Drive OAuth, §4.f Phase 5)

    /// Whether the thin client can actually reach the server right now (a server
    /// DataSource AND a configured `https` base + device token). The CONNECT sheet
    /// uses this to choose its path: the real OAuth round-trip when configured, the
    /// app-wide demo simulation otherwise (everything in the `.local` store is demo
    /// data). `api.isConfigured` is actor-isolated, so this is async.
    var isConnectorBackendConfigured: Bool {
        get async {
            guard DataSource.current.isServer else { return false }
            return await api.isConfigured
        }
    }

    /// One source's connection state, or nil on ANY error (unmapped source string,
    /// not configured, offline, decode). The sheet treats nil as "not connected /
    /// unknown" and shows the CONNECT affordance. Mirrors the calm read-fallback
    /// idiom — a connector status read never surfaces an error banner.
    func connectorStatus(source: String) async -> ConnectorStatusDTO? {
        guard let src = ConnectorSource(rawValue: source) else { return nil }
        guard await api.isConfigured else { return nil }
        return try? await api.connectorStatus(source: src)
    }

    /// Mint a Google consent URL for a source to open in the browser. Throws when
    /// the source string doesn't map to a supported `ConnectorSource`, or when the
    /// server can't reach Google (PRECONDITION_FAILED — GOOGLE_OAUTH_* unset), or
    /// on any transport error. The sheet maps the throw onto its quiet
    /// "can't reach Google yet" state rather than retrying.
    func connectorAuthURL(source: String) async throws -> URL {
        guard let src = ConnectorSource(rawValue: source) else {
            throw AtlasAPIError.badURL   // unmapped source — no consent URL exists
        }
        let dto = try await api.connectorAuthURL(source: src)
        guard let url = URL(string: dto.url) else { throw AtlasAPIError.badURL }
        return url
    }

    // MARK: - Calendar push (§4.e — EventKit is device-only)

    /// Push the device calendar to the server as `calendar` signals. The server
    /// upserts on `(source, externalId)`, so a per-foreground re-push of the same
    /// event updates the existing row instead of duplicating it. Idempotent —
    /// safe to call on every foreground. Returns the count of genuinely new
    /// signals (the ones the worker was enqueued for). No-op when calendar access
    /// isn't granted or the API isn't configured.
    @discardableResult
    func pushCalendarSignals(daysAhead: Int = 14) async -> Int {
        guard EventKitCalendarSource.isAuthorized else { return 0 }
        guard await api.isConfigured else { return 0 }
        let events = EventKitCalendarSource.events(daysAhead: daysAhead)
        let now = Date()
        var enqueued = 0
        for e in events {
            let arrived = e.startOffsetSeconds.map { now.addingTimeInterval($0) } ?? now
            // Build a self-contained, replayable payload (so the outbox can
            // re-send on reconnect without re-reading EventKit). The server
            // upserts on `(source, externalId)`, so a re-push is idempotent.
            let raw = (try? JSONEncoder().encode(e)).flatMap {
                try? JSONDecoder().decode(JSONValue.self, from: $0)
            } ?? .object([:])
            let payload = OutboxPayload.SignalIngestPayload(
                source: SignalSource.calendar.rawValue,
                externalId: e.externalId,
                rawData: raw,
                summary: e.title,
                arrivedAt: AtlasISO.string(arrived)
            )
            // Idempotency: a stable clientRef per (source, externalId) collapses
            // repeated foreground pushes of the same event to one queued item.
            let ref = SyncEngine.calendarClientRef(externalId: e.externalId)
            if upsertOutbox(clientRef: ref, kind: .calendarSignal, payload: .calendarSignal(payload)) {
                enqueued += 1
            }
        }
        await flushOutbox()
        if enqueued > 0 { log.info("queued \(enqueued) calendar signal push(es)") }
        return enqueued
    }

    // MARK: - Sync (delta pull-and-reconcile → cache mirror)

    /// Delta sync (§4.d/§4.e). One-way bootstrap of local-only rows on the first
    /// `.server` run, then flush the durable outbox (so offline mutations land),
    /// then pull every table's deltas by cursor — upserting live rows and
    /// applying tombstones as deletes — into the same `@Model` tables keyed by
    /// server `id`, preserving `@Query` reactivity. Failures degrade to
    /// `.offline`; reads keep serving the cache.
    func sync() async {
        guard await api.isConfigured else { syncState = .offline; return }
        syncState = .syncing
        do {
            // 1) One-way local→server cut-over (idempotent; permanently latches).
            try await bootstrapIfNeeded()
            // 2) Drain queued write-throughs before pulling, so an offline edit
            //    is reflected in the deltas we pull back this same cycle.
            await flushOutbox()
            // 3) Pull deltas by cursor until every table is drained.
            try await deltaSync()
            saveQuietly()
            lastSyncedAt = Date()
            lastError = nil
            syncState = .idle
        } catch let err as AtlasAPIError where err.isOfflineLike {
            syncState = .offline
        } catch {
            lastError = error.localizedDescription
            syncState = .error(error.localizedDescription)
            log.error("sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pull deltas across all synced tables, paging by the durable per-table
    /// cursor until the server reports nothing more. Each page upserts live rows
    /// and deletes tombstoned ones; the cursor is advanced and persisted per page
    /// so a kill mid-drain resumes exactly where it stopped (no skips/repeats —
    /// the `(updatedAt, id)` cursor is total and monotonic).
    private func deltaSync(maxPages: Int = 200) async throws {
        var pages = 0
        while pages < maxPages {
            pages += 1
            let cursors = loadCursors()
            let pull = try await api.syncPull(SyncPullInput(cursors: cursors, limit: SyncEngine.pageLimit))
            applyPull(pull)
            saveQuietly()
            if !pull.hasMore { break }
        }
    }

    /// Apply one `sync.pull` page: dispatch each table's rows to the typed delta
    /// upsert, delete tombstoned rows, and advance + persist each table's cursor.
    private func applyPull(_ pull: SyncPullDTO) {
        for (table, slice) in pull.tables {
            for row in slice.rows { upsertDeltaRow(table: table, row: row) }
            if !slice.tombstones.isEmpty { applyTombstones(table: table, ids: slice.tombstones) }
            if let next = slice.nextCursor {
                saveCursor(table: table, updatedAt: next.updatedAt, id: next.id)
            }
        }
    }

    // MARK: - Cursor persistence (durable per-table resume)

    /// The per-table resume cursors. A table with no stored cursor is OMITTED
    /// (the server treats an absent table as a null/from-scratch cursor), so the
    /// dictionary only carries non-null values.
    private func loadCursors() -> [String: SyncCursorDTO] {
        var out: [String: SyncCursorDTO] = [:]
        let stored = (try? context.fetch(FetchDescriptor<SyncCursor>())) ?? []
        for c in stored where SyncEngine.tables.contains(c.table) {
            out[c.table] = SyncCursorDTO(updatedAt: c.cursorUpdatedAt, id: c.cursorId)
        }
        return out
    }

    private func saveCursor(table: String, updatedAt: String, id: String) {
        let existing = (try? context.fetch(
            FetchDescriptor<SyncCursor>(predicate: #Predicate { $0.table == table })
        ))?.first
        if let c = existing {
            c.cursorUpdatedAt = updatedAt
            c.cursorId = id
        } else {
            context.insert(SyncCursor(table: table, cursorUpdatedAt: updatedAt, cursorId: id))
        }
    }

    /// Quiet single-domain reconciles used after a mutation write-through. These
    /// re-pull the affected tables' deltas without flipping the global
    /// `syncState` chrome, so the Review queue / chapter detail reflect the
    /// server's canonical fan-out (e.g. a new todo from an approved proposal).
    private func syncProposalsQuietly() async {
        await deltaSyncTablesQuietly(["proposals"])
    }
    private func syncChaptersQuietly() async {
        await deltaSyncTablesQuietly(["chapters", "todos", "decisions", "entries", "chapter_links"])
    }

    private func deltaSyncTablesQuietly(_ tables: [String]) async {
        do {
            var pages = 0
            while pages < 50 {
                pages += 1
                let all = loadCursors()
                let cursors = all.filter { tables.contains($0.key) }
                    .reduce(into: [String: SyncCursorDTO]()) { $0[$1.key] = $1.value }
                let pull = try await api.syncPull(
                    SyncPullInput(cursors: cursors, limit: SyncEngine.pageLimit, tables: tables)
                )
                applyPull(pull)
                saveQuietly()
                if !pull.hasMore { break }
            }
        } catch { /* cache stands; the next full sync() reconciles */ }
    }

    // MARK: - Optimistic local helpers

    private func optimisticallyDecide(_ id: UUID, status: ProposalStatus) {
        guard let p = fetchProposal(id) else { return }
        p.status = status
        p.decidedAt = Date()
        saveQuietly()
    }

    // MARK: - Fetch-by-id (cache lookups)

    private func fetchChapter(_ id: UUID) -> Chapter? {
        try? context.fetch(FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchBrief(_ id: UUID) -> Brief? {
        try? context.fetch(FetchDescriptor<Brief>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchWatcher(_ id: UUID) -> Watcher? {
        try? context.fetch(FetchDescriptor<Watcher>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchProposal(_ id: UUID) -> Proposal? {
        try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchTurn(_ id: UUID) -> Turn? {
        try? context.fetch(FetchDescriptor<Turn>(predicate: #Predicate { $0.id == id })).first
    }

    private func saveQuietly() {
        do { try context.save() } catch {
            log.error("context save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Delta upserts (generic SyncRow → @Model, keyed by server id, §4.d)

    /// Dispatch one delta row to its table's typed upsert. Unknown tables are
    /// ignored (forward-compatible with a server that adds a synced table).
    private func upsertDeltaRow(table: String, row: SyncRow) {
        switch table {
        case "chapters":      upsertChapterRow(row)
        case "todos":         upsertTodoRow(row)
        case "decisions":     upsertDecisionRow(row)
        case "entries":       upsertEntryRow(row)
        case "chapter_links": upsertLinkRow(row)
        case "briefs":        upsertBriefRow(row)
        case "watchers":      upsertWatcherRow(row)
        case "signals":       upsertSignalRow(row)
        case "proposals":     upsertProposalRow(row)
        case "turns":         upsertTurnRow(row)
        default:              break
        }
    }

    /// Delete the mirror rows the server tombstoned. For `chapter_links` the
    /// tombstone "id" is the synthetic `from|to|relation` sync key.
    private func applyTombstones(table: String, ids: [String]) {
        for raw in ids {
            switch table {
            case "chapters":      if let id = canonicalUUID(raw), let r = fetchChapter(id)  { context.delete(r) }
            case "todos":         if let id = canonicalUUID(raw), let r = fetchTodo(id)     { context.delete(r) }
            case "decisions":     if let id = canonicalUUID(raw), let r = fetchDecision(id) { context.delete(r) }
            case "entries":       if let id = canonicalUUID(raw), let r = fetchEntry(id)    { context.delete(r) }
            case "briefs":        if let id = canonicalUUID(raw), let r = fetchBrief(id)    { context.delete(r) }
            case "watchers":      if let id = canonicalUUID(raw), let r = fetchWatcher(id)  { context.delete(r) }
            case "signals":       if let id = canonicalUUID(raw), let r = fetchSignal(id)   { context.delete(r) }
            case "proposals":     if let id = canonicalUUID(raw), let r = fetchProposal(id) { context.delete(r) }
            case "turns":         if let id = canonicalUUID(raw), let r = fetchTurn(id)     { context.delete(r) }
            case "chapter_links": if let r = fetchLink(syncKey: raw) { context.delete(r) }
            default: break
            }
        }
    }

    private func upsertChapterRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let ch = fetchChapter(uuid) ?? {
            let c = Chapter(id: uuid, title: row.string("title") ?? "",
                            type: ChapterType(rawValue: row.string("type") ?? "") ?? .personal)
            context.insert(c)
            return c
        }()
        if let t = row.string("title") { ch.title = t }
        if let v = row.string("type") { ch.typeRaw = v }
        if let v = row.string("status") { ch.statusRaw = v }
        ch.startDate = AtlasISO.date(row.string("startDate"))
        ch.endDate = AtlasISO.date(row.string("endDate"))
        ch.purpose = row.string("purpose")
        if let u = AtlasISO.date(row.updatedAt) { ch.updatedAt = u }
        if let c = AtlasISO.date(row.string("createdAt")) { ch.createdAt = c }
    }

    private func upsertTodoRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let t = fetchTodo(uuid) ?? {
            let nt = Todo(id: uuid, text: row.string("text") ?? "")
            context.insert(nt)
            return nt
        }()
        if let v = row.string("text") { t.text = v }
        t.done = row.bool("done") ?? t.done
        t.dueDate = AtlasISO.date(row.string("dueDate"))
        if let v = row.string("source") { t.sourceRaw = v }
        t.doneAt = AtlasISO.date(row.string("doneAt"))
        if let c = AtlasISO.date(row.string("createdAt")) { t.createdAt = c }
        t.chapter = chapterFor(row.string("chapterId")) ?? t.chapter
    }

    private func upsertDecisionRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let d = fetchDecision(uuid) ?? {
            let nd = Decision(id: uuid, title: row.string("title") ?? "")
            context.insert(nd)
            return nd
        }()
        if let v = row.string("title") { d.title = v }
        d.rationale = row.string("rationale")
        d.optionsConsidered = row.string("optionsConsidered")
        if let v = AtlasISO.date(row.string("decidedAt")) { d.decidedAt = v }
        if let c = AtlasISO.date(row.string("createdAt")) { d.createdAt = c }
        d.chapter = chapterFor(row.string("chapterId")) ?? d.chapter
    }

    private func upsertEntryRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let e = fetchEntry(uuid) ?? {
            let ne = Entry(id: uuid, content: row.string("content") ?? "")
            context.insert(ne)
            return ne
        }()
        if let v = AtlasISO.date(row.string("date")) { e.date = v }
        if let v = row.string("content") { e.content = v }
        if let v = row.string("source") { e.sourceRaw = v }
        if let c = AtlasISO.date(row.string("createdAt")) { e.createdAt = c }
        e.chapter = chapterFor(row.string("chapterId")) ?? e.chapter
    }

    /// `chapter_links` has no row id — it keys on the synthetic
    /// `from|to|relation` sync key. We store a deterministic UUIDv5-like id
    /// derived from that key so the local `@Model` (which requires a UUID id)
    /// upserts stably across pulls.
    private func upsertLinkRow(_ row: SyncRow) {
        guard let fromId = canonicalUUID(row.string("fromId")),
              let toId = canonicalUUID(row.string("toId")),
              let relation = row.string("relation"),
              let from = fetchChapter(fromId), let to = fetchChapter(toId)
        else { return }
        let key = SyncEngine.linkSyncKey(fromId: fromId.uuidString, toId: toId.uuidString, relation: relation)
        let linkId = SyncEngine.deterministicUUID(key)
        let link = fetchLink(id: linkId) ?? {
            let nl = ChapterLink(id: linkId, from: from, to: to,
                                 relation: LinkRelation(rawValue: relation) ?? .related)
            context.insert(nl)
            return nl
        }()
        link.fromChapter = from
        link.toChapter = to
        link.relationRaw = relation
        link.note = row.string("note")
        if let c = AtlasISO.date(row.string("createdAt")) { link.createdAt = c }
    }

    private func upsertBriefRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let b = fetchBrief(uuid) ?? {
            let nb = Brief(id: uuid, title: row.string("title") ?? "",
                           situationDescription: row.string("situationDescription") ?? "",
                           structureData: row.jsonData("structure", fallback: "{\"sections\":[]}"))
            context.insert(nb)
            return nb
        }()
        if let v = row.string("title") { b.title = v }
        if let v = row.string("situationDescription") { b.situationDescription = v }
        b.structureData = row.jsonData("structure", fallback: "{\"sections\":[]}")
        if let v = row.string("status") { b.statusRaw = v }
        b.primaryAction = row.string("primaryAction")
        if let secondary = row.json("secondaryActions") {
            b.secondaryActionsJSON = try? JSONEncoder().encode(secondary)
        }
        b.chapterTitle = row.string("chapterTitle")
        b.relevance = row.string("relevance")
        b.when = row.string("when")
        b.drafted = row.string("drafted")
        b.preview = row.string("preview")
        if let s = AtlasISO.date(row.string("surfaceAt")) { b.surfaceAt = s }
        b.expiresAt = AtlasISO.date(row.string("expiresAt"))
        if let c = AtlasISO.date(row.string("createdAt")) { b.createdAt = c }
        b.chapter = chapterFor(row.string("chapterId")) ?? b.chapter
    }

    private func upsertWatcherRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let w = fetchWatcher(uuid) ?? {
            let nw = Watcher(id: uuid, watcherDescription: row.string("description") ?? "",
                             prompt: row.string("prompt") ?? "",
                             nextCheck: AtlasISO.date(row.string("nextCheck")) ?? Date())
            context.insert(nw)
            return nw
        }()
        if let v = row.string("description") { w.watcherDescription = v }
        if let v = row.string("prompt") { w.prompt = v }
        if let v = row.string("sourceType") { w.sourceTypeRaw = v }
        w.lastChecked = AtlasISO.date(row.string("lastChecked"))
        if let n = AtlasISO.date(row.string("nextCheck")) { w.nextCheck = n }
        if let v = row.int("cadenceMinutes") { w.cadenceMinutes = v }
        if let v = row.string("status") { w.statusRaw = v }
        w.cadenceLabel = row.string("cadenceLabel")
        if let c = AtlasISO.date(row.string("createdAt")) { w.createdAt = c }
        w.chapter = chapterFor(row.string("chapterId")) ?? w.chapter
    }

    private func upsertSignalRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let s = fetchSignal(uuid) ?? {
            // `Signal.init` requires a SignalSource + rawData; build a minimal
            // row then overwrite the blob from the server `rawData` value.
            let ns = Signal(id: uuid,
                            source: SignalSource(rawValue: row.string("source") ?? "") ?? .manual,
                            externalId: row.string("externalId"),
                            rawData: EmptyJSON())
            context.insert(ns)
            return ns
        }()
        if let v = row.string("source") { s.sourceRaw = v }
        s.externalId = row.string("externalId")
        s.rawDataJSON = row.jsonData("rawData")
        s.summary = row.string("summary")
        s.processed = row.bool("processed") ?? s.processed
        if let a = AtlasISO.date(row.string("arrivedAt")) { s.arrivedAt = a }
    }

    private func upsertProposalRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let p = fetchProposal(uuid) ?? {
            let np = Proposal(id: uuid,
                              type: ProposalType(rawValue: row.string("type") ?? "") ?? .todo,
                              proposedPayload: EmptyJSON(),
                              confidence: row.double("confidence") ?? 0.5)
            context.insert(np)
            return np
        }()
        if let v = row.string("type") { p.typeRaw = v }
        p.proposedPayloadJSON = row.jsonData("proposedPayload")
        if let v = row.string("status") { p.statusRaw = v }
        if let v = row.double("confidence") { p.confidence = v }
        p.reasoning = row.string("reasoning")
        p.summary = row.string("summary")
        p.sourceLabel = row.string("sourceLabel")
        p.sourceMeta = row.string("sourceMeta")
        p.question = row.string("question")
        p.setup = row.string("setup")
        if let opts = row.json("options") { p.optionsJSON = try? JSONEncoder().encode(opts) }
        p.decidedAt = AtlasISO.date(row.string("decidedAt"))
        if let c = AtlasISO.date(row.string("createdAt")) { p.createdAt = c }
        p.sourceBriefId = canonicalUUID(row.string("sourceBriefId"))
        p.chapter = chapterFor(row.string("chapterId")) ?? p.chapter
    }

    /// Upsert a `turns` row (Today agentic flow v1) — mirrors `upsertBriefRow`.
    /// role/kind/body/sourceTag are scalar strings; briefIds/memo/connector/meta
    /// are nested JSON blobs stored as-is (nil when the server value is absent),
    /// decoded lazily by the `@Model`'s computed accessors. Timestamps via
    /// `AtlasISO.date` like every other table.
    private func upsertTurnRow(_ row: SyncRow) {
        guard let uuid = canonicalUUID(row.id) else { return }
        let t = fetchTurn(uuid) ?? {
            let nt = Turn(id: uuid,
                          role: TurnRole(rawValue: row.string("role") ?? "") ?? .ayumi,
                          kind: TurnKind(rawValue: row.string("kind") ?? "") ?? .message,
                          body: row.string("body") ?? "")
            context.insert(nt)
            return nt
        }()
        if let v = row.string("role") { t.roleRaw = v }
        if let v = row.string("kind") { t.kindRaw = v }
        if let v = row.string("body") { t.body = v }
        t.sourceTag = row.string("sourceTag")
        // The four JSON blobs: keep the server value verbatim (re-encoded to
        // bytes) so the keys round-trip; nil when the json value is absent/null.
        t.briefIdsJSON = jsonBlob(row, "briefIds")
        t.memoJSON     = jsonBlob(row, "memo")
        t.connectorJSON = jsonBlob(row, "connector")
        t.metaJSON     = jsonBlob(row, "meta")
        if let u = AtlasISO.date(row.updatedAt) { t.updatedAt = u }
        if let c = AtlasISO.date(row.string("createdAt")) { t.createdAt = c }
    }

    /// Re-encode a nested JSON value to bytes for a NILABLE `@Model` blob field —
    /// nil when the server omitted the key / sent null (unlike `row.jsonData`,
    /// which always returns a fallback). Used for `turns`' optional json columns.
    private func jsonBlob(_ row: SyncRow, _ key: String) -> Data? {
        guard let v = row.json(key) else { return nil }
        return try? JSONEncoder().encode(v)
    }

    // MARK: - Durable outbox (write-through queue, §4.d/§4.e)

    /// Enqueue a write-through with a fresh `clientRef`. The optimistic local row
    /// has already been written; this makes the server write-through durable.
    @discardableResult
    private func enqueue(_ payload: OutboxPayload) -> Bool {
        let kind: OutboxKind = {
            switch payload {
            case .approve:        return .approve
            case .dismiss:        return .dismiss
            case .briefAct:       return .briefAct
            case .calendarSignal: return .calendarSignal
            case .memoStrike:     return .memoStrike
            case .memoKeep:       return .memoKeep
            }
        }()
        return upsertOutbox(clientRef: UUID(), kind: kind, payload: payload)
    }

    /// Enqueue/refresh an item under a SPECIFIC `clientRef` (idempotent enqueue —
    /// used by the calendar push so repeated foregrounds collapse to one item).
    /// Returns true if a NEW item was created.
    @discardableResult
    private func upsertOutbox(clientRef: UUID, kind: OutboxKind, payload: OutboxPayload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        if let existing = fetchOutbox(clientRef) {
            existing.payloadJSON = data
            existing.kindRaw = kind.rawValue
            saveQuietly()
            return false
        }
        context.insert(OutboxItem(clientRef: clientRef, kind: kind, payloadJSON: data))
        saveQuietly()
        return true
    }

    /// Flush the durable outbox oldest-first. Each item replays its write-through
    /// idempotently (server dedupes by clientRef / guards transitions). An
    /// offline error stops the drain (the queue stands for the next reconnect); a
    /// poison item (4xx/validation) is dropped after `outboxMaxAttempts` so it
    /// can't block the queue forever.
    func flushOutbox() async {
        guard await api.isConfigured else { return }
        let items = (try? context.fetch(
            FetchDescriptor<OutboxItem>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )) ?? []
        for item in items {
            do {
                try await replay(item)
                context.delete(item)   // applied — drop it
                saveQuietly()
            } catch let err as AtlasAPIError where err.isOfflineLike {
                syncState = .offline
                return   // stop the drain; the queue stands for the next reconnect
            } catch {
                item.attempts += 1
                item.lastError = error.localizedDescription
                if item.attempts >= SyncEngine.outboxMaxAttempts {
                    log.error("dropping poison outbox item \(item.clientRef, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    context.delete(item)
                }
                saveQuietly()
                // A hard per-item failure shouldn't block items behind it; continue.
            }
        }
    }

    /// Replay one outbox item against the API. The item's `clientRef` is the
    /// idempotency key the server dedupes on.
    private func replay(_ item: OutboxItem) async throws {
        guard let payload = try? JSONDecoder().decode(OutboxPayload.self, from: item.payloadJSON) else {
            throw AtlasAPIError.badURL   // undecodable → treat as poison
        }
        switch payload {
        case let .approve(id, chosenValue):
            _ = try await api.proposalApprove(ApproveInput(id: id, chosenValue: chosenValue))
        case let .dismiss(id):
            _ = try await api.proposalDismiss(id)
        case let .briefAct(id, action):
            let act = BriefAction(rawValue: action) ?? .start
            _ = try await api.briefAct(id: id, action: act)
        case let .calendarSignal(p):
            _ = try await api.signalIngest(SignalIngestInput(
                source: p.source, externalId: p.externalId,
                rawData: AnyEncodableValue(p.rawData),
                summary: p.summary, arrivedAt: p.arrivedAt
            ))
        case let .memoStrike(turnId, lineId, struck):
            _ = try await api.turnStrike(turnId: turnId, lineId: lineId, struck: struck)
        case let .memoKeep(turnId):
            _ = try await api.turnKeep(turnId: turnId)
        }
    }

    private func fetchOutbox(_ ref: UUID) -> OutboxItem? {
        try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.clientRef == ref })).first
    }

    /// Whether there are queued write-throughs waiting to flush (Settings chrome).
    var pendingOutboxCount: Int {
        (try? context.fetchCount(FetchDescriptor<OutboxItem>())) ?? 0
    }

    // MARK: - One-way local→server bootstrap (§4.d)

    /// Run the `local→server` cut-over exactly once, latched durably. Uploads the
    /// rows a device created under the OLD on-device brain (before sync existed)
    /// so they aren't lost, rewrites their local ids to the server-assigned ids,
    /// and marks the migration done — after which the client PERMANENTLY stops
    /// local generation for synced types and never re-runs the bootstrap (§4.d).
    ///
    /// IMPORTANT — what is NOT uploaded: a fresh `.server` install seeds the
    /// mirror with demo rows (`Seed`/`SeedV2`) purely as cold-start UI. Those are
    /// NOT user data and must never be pushed to the user's real server. So the
    /// upload runs ONLY when a genuine local-origin marker is present
    /// (`UserDefaults["AtlasLocalOriginData"]` — set by the developer `.local`
    /// path when it created real data, or the `--bootstrap-local` launch arg).
    /// Without that marker the migration latches immediately and the client
    /// becomes a pure read-mirror of the server's authoritative data.
    ///
    /// The upload is idempotent: each row carries its local id as `clientRef` and
    /// the server upserts by `(userId, clientRef)`, so a re-run (e.g. the first
    /// attempt failed offline) resolves to the same server ids and the mapping is
    /// stable — no duplication.
    private func bootstrapIfNeeded() async throws {
        let migration = loadMigration()
        guard !migration.bootstrapped else { return }   // already cut over — never again

        // Gate: only a device with genuine local-origin data uploads. A normal
        // fresh `.server` install (demo seeds only) latches without uploading.
        guard Self.hasLocalOriginData else {
            markBootstrapped(migration)
            return
        }

        let chapters = (try? context.fetch(FetchDescriptor<Chapter>())) ?? []
        guard !chapters.isEmpty else {
            // Nothing local to upload — latch immediately so we never re-check.
            markBootstrapped(migration)
            return
        }

        var input = BootstrapInput()
        for c in chapters {
            input.chapters.append(.init(
                clientRef: c.id.uuidString.lowercased(),
                title: c.title, type: c.typeRaw, status: c.statusRaw,
                startDate: c.startDate.map(AtlasISO.string),
                endDate: c.endDate.map(AtlasISO.string),
                purpose: c.purpose,
                createdAt: AtlasISO.string(c.createdAt),
                updatedAt: AtlasISO.string(c.updatedAt)
            ))
            for t in c.todos {
                input.todos.append(.init(
                    clientRef: t.id.uuidString.lowercased(),
                    chapterRef: c.id.uuidString.lowercased(),
                    text: t.text, done: t.done,
                    dueDate: t.dueDate.map(AtlasISO.string),
                    source: t.sourceRaw,
                    createdAt: AtlasISO.string(t.createdAt),
                    updatedAt: AtlasISO.string(t.createdAt)
                ))
            }
            for d in c.decisions {
                input.decisions.append(.init(
                    clientRef: d.id.uuidString.lowercased(),
                    chapterRef: c.id.uuidString.lowercased(),
                    title: d.title, rationale: d.rationale,
                    optionsConsidered: d.optionsConsidered,
                    decidedAt: AtlasISO.string(d.decidedAt),
                    source: "manual",
                    createdAt: AtlasISO.string(d.createdAt),
                    updatedAt: AtlasISO.string(d.createdAt)
                ))
            }
            for e in c.entries {
                input.entries.append(.init(
                    clientRef: e.id.uuidString.lowercased(),
                    chapterRef: c.id.uuidString.lowercased(),
                    date: AtlasISO.string(e.date),
                    content: e.content, source: e.sourceRaw,
                    createdAt: AtlasISO.string(e.createdAt),
                    updatedAt: AtlasISO.string(e.createdAt)
                ))
            }
        }

        // Upload + receive the localId→serverId maps. Throws on offline so sync()
        // degrades to `.offline` and retries the cut-over next foreground (the
        // migration stays un-latched until the upload succeeds).
        let result = try await api.syncBootstrap(input)

        // Rewrite local ids to the server-assigned ids so subsequent pulls upsert
        // onto the SAME row instead of duplicating (ID parity, §4.d). Child FKs
        // ride the SwiftData relationship, so re-pointing the chapter is enough
        // for the parent edge; child ids are rewritten directly.
        rewriteIds(map: result.mapping.chapters, in: Chapter.self, get: { $0.id }, set: { $0.id = $1 })
        rewriteIds(map: result.mapping.todos, in: Todo.self, get: { $0.id }, set: { $0.id = $1 })
        rewriteIds(map: result.mapping.decisions, in: Decision.self, get: { $0.id }, set: { $0.id = $1 })
        rewriteIds(map: result.mapping.entries, in: Entry.self, get: { $0.id }, set: { $0.id = $1 })

        markBootstrapped(migration)
        saveQuietly()
    }

    /// Rewrite a table's local ids using a `localId(lowercased UUID) → serverId`
    /// map. The local row keyed by the old (clientRef) id gets the new server id.
    private func rewriteIds<M: PersistentModel>(
        map: [String: String], in _: M.Type,
        get: (M) -> UUID, set: (M, UUID) -> Void
    ) {
        let rows = (try? context.fetch(FetchDescriptor<M>())) ?? []
        for row in rows {
            let local = get(row).uuidString.lowercased()
            guard let serverIdStr = map[local], let serverId = canonicalUUID(serverIdStr) else { continue }
            if get(row) != serverId { set(row, serverId) }
        }
    }

    /// Whether this device carries genuine local-origin data that must be
    /// preserved by the one-way cut-over. True only when the developer `.local`
    /// path recorded real data (`UserDefaults["AtlasLocalOriginData"] == true`)
    /// or the `--bootstrap-local` launch arg is present. False on a normal fresh
    /// `.server` install — so demo seeds are never pushed to the server.
    static var hasLocalOriginData: Bool {
        if ProcessInfo.processInfo.arguments.contains("--bootstrap-local") { return true }
        return UserDefaults.standard.bool(forKey: "AtlasLocalOriginData")
    }

    private func loadMigration() -> SyncMigration {
        if let m = try? context.fetch(FetchDescriptor<SyncMigration>()).first { return m }
        let m = SyncMigration()
        context.insert(m)
        saveQuietly()
        return m
    }

    private func markBootstrapped(_ m: SyncMigration) {
        m.bootstrapped = true
        m.bootstrappedAt = Date()
        saveQuietly()
    }

    /// Whether the one-way cut-over has completed (Settings chrome).
    var hasBootstrapped: Bool {
        (try? context.fetch(FetchDescriptor<SyncMigration>()).first)?.bootstrapped ?? false
    }

    // MARK: - Delta fetch-by-id helpers

    private func fetchTodo(_ id: UUID) -> Todo? {
        try? context.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchDecision(_ id: UUID) -> Decision? {
        try? context.fetch(FetchDescriptor<Decision>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchEntry(_ id: UUID) -> Entry? {
        try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchSignal(_ id: UUID) -> Signal? {
        try? context.fetch(FetchDescriptor<Signal>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchLink(id: UUID) -> ChapterLink? {
        try? context.fetch(FetchDescriptor<ChapterLink>(predicate: #Predicate { $0.id == id })).first
    }
    /// Resolve a link by its synthetic `from|to|relation` sync key (tombstones).
    private func fetchLink(syncKey: String) -> ChapterLink? {
        guard let id = SyncEngine.uuidForLinkSyncKey(syncKey) else { return nil }
        return fetchLink(id: id)
    }

    /// Parse a server text-UUID (canonical lowercase) into a `UUID`. iOS `@Model`
    /// ids are uppercase-serialized, but `UUID(uuidString:)` is case-insensitive,
    /// so a lowercase server id round-trips to the SAME `UUID` — that is the ID
    /// parity guarantee (§4.d).
    private func canonicalUUID(_ s: String?) -> UUID? {
        guard let s, !s.isEmpty else { return nil }
        return UUID(uuidString: s)
    }

    private func chapterFor(_ id: String?) -> Chapter? {
        canonicalUUID(id).flatMap { fetchChapter($0) }
    }
}

// ════════════════════════════════════════════════════════════════════
//  v0.7 — Capture co-completion + the Living Chapter (North India).
//
//  Wired to the real server endpoints (modules MC/MD): `capture.complete` /
//  `capture.file` and `trip.get` / `trip.correct` / `trip.grantConnector`.
//  The brain stays server-side — `complete` enqueues a `capture_complete`
//  one_shot job the WORKER drains through the single gateway (the app NEVER
//  calls Anthropic); the trip reconcile + connector grant are real mutations
//  with a deterministic recompute + a durable learned preference.
//
//  Every method keeps a SEEDED fallback (README §PART 2) so the `.local`
//  DataSource and the offline/unconfigured paths render faithfully with no
//  network. Pure additions — they do not touch the sync/outbox machinery.
// ════════════════════════════════════════════════════════════════════
extension AtlasRepo {

    // MARK: - Capture (co-completion + file)

    /// What `completeCapture` returns to the `CaptureController`: a ghost
    /// remainder + the forming structure + an optional one-question.
    struct CaptureCompletionResult {
        var ghost: String
        var kind: String          // "todo" | "decision" | "note"
        var chapterId: String?
        var tag: String
        var generic: Bool
        var question: CaptureQuestion?
    }

    /// Co-complete a fragment (README §"Co-completion model"). REAL backend
    /// (`.server` + configured): `capture.complete` — the worker runs the
    /// streaming ghost + the kind/chapter classifier through the single gateway
    /// (Haiku one_shot) and the server polls the job to completion, returning the
    /// structured `{ghost, kind, chapterId, question}`. Offline / `.local`:
    /// resolve against the seeded dictionary so the well co-completes faithfully.
    func completeCapture(_ fragment: String) async -> CaptureCompletionResult {
        // Server path — the real co-completion. The server returns the structure;
        // the forming-tag *suffix* is a display string we derive here.
        if DataSource.current.isServer, await api.isConfigured {
            do {
                let r = try await api.captureComplete(
                    CaptureCompleteInput(fragment: fragment)
                )
                // A confident match has a non-empty ghost OR a concrete chapter; an
                // empty ghost + no chapter is the calm auto-file fallback.
                let generic = r.ghost.isEmpty && r.chapterId == nil
                let question = r.question.map {
                    CaptureQuestion(text: $0.text, answers: $0.answers)
                }
                return CaptureCompletionResult(
                    ghost: r.ghost,
                    kind: r.kind,
                    chapterId: r.chapterId,
                    tag: Self.formingTagSuffix(kind: r.kind, chapterId: r.chapterId,
                                               generic: generic),
                    generic: generic,
                    question: question
                )
            } catch {
                log.info("captureComplete fell back to seed: \(error.localizedDescription, privacy: .public)")
                // Fall through to the seeded dictionary on any transport/decode error.
            }
        }

        // Offline / `.local` fallback — the seeded co-completion dictionary.
        let c = CaptureController.dictionaryCompletion(for: fragment)
        guard let match = c.match else {
            return CaptureCompletionResult(ghost: "", kind: "note", chapterId: nil,
                                           tag: "auto-filed", generic: true, question: nil)
        }
        return CaptureCompletionResult(
            ghost: c.ghost, kind: match.kind.rawValue, chapterId: match.chapterId,
            tag: match.tag, generic: match.generic, question: c.question
        )
    }

    /// Derive the forming-tag suffix ("Stratyfix · due Tue" / "auto-filed") the
    /// well renders after the kind. The server returns the *structure* (kind +
    /// chapter), not the display string; this maps a chapter id to its title and
    /// keeps the calm auto-file label for the generic case.
    private static func formingTagSuffix(kind: String, chapterId: String?, generic: Bool) -> String {
        if generic { return "auto-filed" }
        guard let chapterId, !chapterId.isEmpty else {
            // No chapter — file to the day's thread (matches the "today" tag).
            return "today"
        }
        // Prefer a seeded chapter title (so "stratyfix" → "Stratyfix"); otherwise
        // titlecase the id as a sane default.
        if let seeded = CaptureController.predictions.first(where: { $0.chapterId == chapterId }) {
            return seeded.tag
        }
        return chapterId.prefix(1).uppercased() + chapterId.dropFirst()
    }

    /// File a completed capture (README §"A filed state"). REAL backend
    /// (`.server` + configured): `capture.file` — a "file note" mutation that
    /// emits a `capture_received` event the worker fans into the right todo/
    /// decision/note row (re-classifying if `kind`/`chapterId` were left to her).
    /// Offline / `.local`: a no-op — the optimistic "Kept." confirmation stands
    /// and the intent can be retried on reconnect.
    func fileCapture(text: String, kind: String, chapterId: String?, answer: String?,
                     source: String = "text") async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard DataSource.current.isServer, await api.isConfigured else {
            return   // offline / `.local` → the UI confirmation stands
        }
        do {
            _ = try await api.captureFile(
                CaptureFileInput(text: trimmed, kind: kind, chapterId: chapterId,
                                 answer: answer, source: source)
            )
            // The worker classifies + files asynchronously; pull any produced
            // proposals into the cache so the Review queue + result turns render.
            await syncProposalsQuietly()
        } catch {
            log.info("captureFile failed (kept locally): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - The Living Chapter (North India)

    /// The seeded North India projection (README §PART 2) — the instant, offline
    /// render. Opened mid-trip (day 5, Rishikesh), with the Delhi→Nainital leg
    /// deliberately WRONG ("Flew to Pantnagar · ₹4,900") so the correction has
    /// something real to fix. The view shows this immediately, then upgrades to
    /// the server projection via `loadTrip(id:)`.
    func northIndiaTrip() -> Trip { NorthIndiaSeed.northIndia }

    /// Fetch the Living Chapter from the server and MERGE it onto the rich seed.
    ///
    /// REAL backend (`.server` + configured): `trip.get` returns the lean
    /// reasoning model (the seed + the caller's persisted overlay — their
    /// corrections + connector grants — + learned preferences) so a corrected leg,
    /// a rebalanced spend, and a granted connector survive across reads. The seed
    /// carries the design-only extras the server shape omits (icons, sparklines,
    /// build-steps, the correction sheets, the framing accent), so we overlay the
    /// server's mutable facts (stops/legs/spend/connectors/recs/tracking/receipts)
    /// onto the seed by id. Offline / `.local`: returns the seed unchanged.
    func loadTrip(id: String) async -> Trip {
        let seed = NorthIndiaSeed.northIndia
        guard DataSource.current.isServer, await api.isConfigured else { return seed }
        do {
            guard let dto = try await api.tripGet(id) else { return seed }
            return Self.mergeTrip(seed: seed, dto: dto)
        } catch {
            log.info("tripGet fell back to seed: \(error.localizedDescription, privacy: .public)")
            return seed
        }
    }

    /// Reconcile a correction on a past leg (README §A). REAL backend (`.server` +
    /// configured): `trip.correct` — a real mutation + a deterministic recompute
    /// over the trip model (rewrite the leg, rebalance spend, PERSIST a learned
    /// preference that tunes the NEXT suggestion). Returns the ripple {changed,
    /// learned}; the view applies the leg/spend patch. Offline / `.local`: the
    /// seeded reconcile maps the answer to the same outcome locally.
    func correctLeg(legId: String, answer: String) async -> (ripple: Ripple, learned: String) {
        if DataSource.current.isServer, await api.isConfigured {
            do {
                let r = try await api.tripCorrect(
                    TripCorrectInput(targetId: legId, answer: answer)
                )
                return (Ripple(changed: r.ripple.changed, learned: r.learned), r.learned)
            } catch {
                log.info("tripCorrect fell back to seed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let r = NorthIndiaSeed.reconcile(legId: legId, answer: answer)
        return (r, r.learned)
    }

    /// Grant a connector (README §6). REAL backend (`.server` + configured):
    /// `trip.grantConnector` — flips the source available→feeding, rewrites what
    /// she can now do, persists the grant, and marks the chapter for re-derivation
    /// (a real build backfills + re-derives affected sections). Idempotent.
    /// Offline / `.local`: a no-op — the view applies the optimistic relabel from
    /// the connector's `unlockCopy`. Returns the rewritten role/unlock copy on the
    /// server path (nil offline) so the view can adopt the server's wording.
    @discardableResult
    func grantConnector(_ id: String) async -> (role: String, unlockCopy: String)? {
        guard DataSource.current.isServer, await api.isConfigured else {
            log.info("grantConnector offline (optimistic relabel): \(id, privacy: .public)")
            return nil
        }
        do {
            let r = try await api.tripGrantConnector(TripGrantConnectorInput(id: id))
            return (r.role, r.unlockCopy)
        } catch {
            log.info("grantConnector failed (kept optimistic): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Trip merge (server lean model → rich seed)

    /// Overlay the server's mutable facts onto the rich seed by id. The seed owns
    /// the design-only extras the server shape omits (icons, sparkline samples,
    /// progress dots, build-steps, correction sheets, the framing accent); the
    /// server owns the *state* (a corrected leg, the rebalanced spend, a granted
    /// connector, the live tracking values). We keep the seed's structure and copy
    /// where the server is silent, and adopt the server's values where it speaks.
    static func mergeTrip(seed: Trip, dto: TripDTO) -> Trip {
        var trip = seed

        // Top-level framing — adopt the server's copy, keep the seed's accent so
        // the teal highlight still lands.
        trip.title = dto.title.hasSuffix(".") ? String(dto.title.dropLast()) : dto.title
        trip.framing = dto.framing
        trip.dateRange = dto.dateRange
        trip.meta = dto.meta

        // Stops — overlay note/mini/dates/state/provenance/collapsed by id.
        trip.stops = seed.stops.map { s in
            guard let d = dto.stops.first(where: { $0.id == s.id }) else { return s }
            var stop = s
            stop.place = d.place
            stop.dates = d.dates
            stop.note = d.note
            stop.mini = d.mini
            stop.state = Stop.StopState(rawValue: d.state) ?? s.state
            let prov = d.provenance.compactMap { Provenance(rawValue: $0) }
            if !prov.isEmpty { stop.provenance = prov }
            stop.collapsed = d.collapsed
            return stop
        }

        // Legs — the mutable heart: a corrected leg carries the new mode/fare and
        // flips to the `told` style.
        trip.legs = seed.legs.map { l in
            guard let d = dto.legs.first(where: { $0.id == l.id }) else { return l }
            var leg = l
            leg.mode = d.mode
            leg.why = d.why
            leg.fare = d.fare
            leg.booked = d.booked
            leg.corrected = d.correctedByUser
            return leg
        }

        // Spend — adopt the server's recomputed total + segment breakdown so a
        // persisted correction's rebalance is reflected on load.
        var spend = seed.spend
        spend.total = dto.spend.total
        spend.projected = dto.spend.projected
        for seg in dto.spend.segments {
            switch seg.key {
            case "flights": spend.segments.flights = seg.amount
            case "stays":   spend.segments.stays = seg.amount
            case "food":    spend.segments.food = seg.amount
            case "travel":  spend.segments.travel = seg.amount
            default: break
            }
        }
        if !dto.spend.sources.isEmpty { spend.sources = dto.spend.sources }
        trip.spend = spend

        // Recommendations — overlay copy by id (keep the seed's thumb gradient).
        trip.recommendations = seed.recommendations.map { r in
            guard let d = dto.recommendations.first(where: { $0.id == r.id }) else { return r }
            var rec = r
            rec.text = d.title
            rec.tasteSignal = d.signal
            return rec
        }

        // Tracking — overlay the live value/sub by id (keep dots/bars/wide layout).
        trip.tracking = seed.tracking.map { t in
            guard let d = dto.tracking.first(where: { $0.id == t.id }) else { return t }
            var stat = t
            stat.value = d.value
            stat.sub = d.detail.isEmpty ? t.sub : d.detail
            return stat
        }

        // Connectors — overlay status + role + unlock copy by id (so a persisted
        // grant shows "feeding" with the rewritten role on load).
        trip.connectors = seed.connectors.map { c in
            guard let d = dto.connectors.first(where: { $0.id == c.id }) else { return c }
            var conn = c
            conn.name = d.name
            conn.role = d.role
            conn.status = Connector.Status(rawValue: d.status) ?? c.status
            if !d.unlockCopy.isEmpty { conn.unlockCopy = d.unlockCopy }
            return conn
        }

        // Receipts (source-sheet rows) — keep the seed's icon-rich TripReceipts;
        // the build-steps + corrections are design-only and stay seeded.
        return trip
    }
}

// MARK: - North India seed (README §PART 2 — illustrative demo content)

/// The seeded Living Chapter content. All amounts / place names / the "Flew to
/// Pantnagar" wrong guess / search-history justifications / connector names are
/// ILLUSTRATIVE (README "A note on scope of the demo data") — they make the
/// reasoning legible. A later phase replaces this with real derivation.
enum NorthIndiaSeed {

    // ── Stops (route) ────────────────────────────────────────────────
    static let stops: [Stop] = [
        Stop(id: "delhi", place: "Delhi", dates: "May 30 · DEL",
             note: "Landed IndiGo 6E-2043, overnight near the airport before heading up to the hills.",
             mini: "Landed · cab held · 40 min on the ground.",
             state: .done, provenance: [.booked], collapsed: true),
        Stop(id: "nainital", place: "Nainital", dates: "May 30 – Jun 2",
             note: "Three nights by the lake. Boating at Naini, the Mall Road evenings, a day up to Tiffin Top.",
             mini: "3 nights by the lake · Tiffin Top at dawn.",
             state: .done, provenance: [.inferred, .live], collapsed: true),
        Stop(id: "rishikesh", place: "Rishikesh", dates: "Jun 2 – 6 · now",
             note: "You're here. Ganga aarti tonight at Parmarth — I set a 6:15 nudge.",
             mini: "Day 5 — you're here.",
             // No provenance chip on the active stop — the reference `.here` stop
             // shows only the "YOU'RE HERE · MAPS" / "STAY ENDS JUN 6" action tags,
             // not a standalone 'LIVE' know-chip (StopRow renders those tags).
             state: .here, provenance: [], collapsed: false),
        Stop(id: "kasol", place: "Kasol", dates: "27–29 May",
             note: "I added this — you searched “Kheerganga trek” twice in April. Two nights in Parvati Valley, the obvious base for the trek.",
             mini: "Inferred from your searches.",
             state: .upcoming, provenance: [.inferred], collapsed: false),
        Stop(id: "chandigarh", place: "Chandigarh", dates: "29–30 May",
             note: "Out the same way you’ll fly home — IndiGo 6E-185, Chandigarh → Delhi → home.",
             mini: "Fly home from here.",
             state: .upcoming, provenance: [.booked], collapsed: false),
    ]

    // ── Legs (ground transport between stops) ────────────────────────
    //
    // Leg ids are `leg-<toStop>` — BYTE-MATCHED to the server seed
    // (src/server/routers/trip.ts), so `mergeTrip` adopts a persisted server leg
    // patch and `correctLeg` hits the scripted reconcile rule online. NOTE the ids
    // intentionally differ from the stop ids: the collapse/expand + correction
    // code keys off `leg.toStop` (the corrected past stop), never the leg id.
    static let legs: [Leg] = [
        // Deliberately WRONG seed — the correction target (README §A).
        Leg(id: "leg-nainital", mode: "Flew to Pantnagar", why: "Quickest hop off the plains — a short flight, then the climb up.",
            fare: "₹4,900", booked: true, fromStop: "delhi", toStop: "nainital"),
        Leg(id: "leg-rishikesh", mode: "Shared taxi · Nainital → Rishikesh", why: "Overnight like your Manali run — saved a day on the road.",
            fare: "₹2,100", booked: true, fromStop: "nainital", toStop: "rishikesh"),
        // Unbooked suggestion — profile-tuned reasoning (README §"The route").
        Leg(id: "leg-kasol", mode: "Overnight to Bhuntar, cab to Kasol", why: "You get carsick on switchbacks — I’d split it overnight at Bhuntar, then a short cab in.",
            fare: "", booked: false, fromStop: "rishikesh", toStop: "kasol"),
        Leg(id: "leg-chandigarh", mode: "Volvo to Chandigarh", why: "Lines up with your morning flight — leaves you a buffer at the airport.",
            fare: "", booked: false, fromStop: "kasol", toStop: "chandigarh"),
    ]

    // ── Spend (README §3) ────────────────────────────────────────────
    static let spend = Spend(
        total: 34_750, projected: 68_000,
        segments: .init(flights: 12_400, stays: 13_900, food: 5_650, travel: 2_800),
        sources: [
            "Bookings (flights, stays) read from your inbox. Food from your card-swipe SMS.",
            "The two unbooked legs — Rishikesh → Kasol and Kasol → Chandigarh — aren’t counted yet.",
        ]
    )

    // ── Recommendations (README §4) ──────────────────────────────────
    static let recommendations: [Recommendation] = [
        Recommendation(id: "bluetokai", text: "Blue Tokai", place: "RISHIKESH · 400M AWAY",
                       tasteSignal: "you rate specialty coffee everywhere — Blue Tokai is your most-visited place back home.",
                       thumb: "r1"),
        Recommendation(id: "kheerganga", text: "Kheerganga trek", place: "KASOL · YOUR NEXT STOP",
                       tasteSignal: "matches the trek you searched twice in April — the hot springs at the top are the payoff.",
                       thumb: "r2"),
    ]

    // ── Tracking (README §5) ─────────────────────────────────────────
    static let tracking: [TrackingStat] = [
        TrackingStat(id: "places", label: "PLACES VISITED", value: "2", unit: "of 5",
                     sub: "Delhi · Nainital · here", kind: .dots,
                     dots: [.on, .on, .here, .off, .off]),
        TrackingStat(id: "steps", label: "TODAY’S STEPS", value: "11.4k", unit: nil,
                     sub: "Apple Health", kind: .bars,
                     bars: [.init(height: 0.4, dim: true), .init(height: 0.6, dim: false),
                            .init(height: 0.9, dim: false), .init(height: 0.7, dim: false),
                            .init(height: 1.0, dim: false), .init(height: 0.5, dim: true),
                            .init(height: 0.3, dim: true)]),
        TrackingStat(id: "totals", label: "TRIP SO FAR", value: "58k", unit: "steps",
                     sub: "1,240m climbed · 5 days · Health + Maps", kind: .plain, wide: true),
    ]

    // ── Connectors (README §6) ───────────────────────────────────────
    static let connectors: [Connector] = [
        Connector(id: "gmail", name: "Gmail", role: "Reading bookings — your flights and stays.",
                  status: .feeding, unlockCopy: "", icon: "gmail"),
        Connector(id: "health", name: "Apple Health", role: "Counting steps and the climb up the hills.",
                  status: .feeding, unlockCopy: "", icon: "health"),
        Connector(id: "maps", name: "Maps", role: "Confirming where you actually are — Rishikesh, day 5.",
                  status: .feeding, unlockCopy: "", icon: "maps"),
        // grantedRole strings BYTE-MATCH the server's grantCopyFor() role
        // (src/server/routers/trip.ts) so the post-grant copy is identical
        // offline and online — the row never re-words when the server path lands.
        Connector(id: "hdfc", name: "HDFC card", role: "Where your money’s going on the ground.",
                  status: .available,
                  unlockCopy: "I’d read your card swipes — exact food + travel spend, not an estimate.",
                  grantedRole: "Itemising food and local spend from card-swipe SMS.",
                  icon: "bank"),
        Connector(id: "irctc", name: "IRCTC rail", role: "Live trains for the legs I haven’t booked.",
                  status: .available,
                  unlockCopy: "I’d hold real sleeper berths for the Kasol leg instead of guessing.",
                  grantedRole: "Watching sleeper seats on the Kasol leg.",
                  icon: "rail"),
        Connector(id: "calendar", name: "Calendar", role: "What’s waiting for you back home.",
                  status: .available,
                  unlockCopy: "I’d work the trip around your first day back — and warn you about the clash on the 31st.",
                  grantedRole: "Planning the return around your week back.",
                  icon: "cal"),
    ]

    // ── Receipts (README §7) ─────────────────────────────────────────
    static let receipts: [TripReceipt] = [
        TripReceipt(id: "flight-in", kind: "EMAIL", ref: "IndiGo 6E-2043 · DEL · 18 May — your arrival.", icon: "email"),
        TripReceipt(id: "flight-out", kind: "EMAIL", ref: "IndiGo 6E-185 · IXC→DEL · 30 May — your way home.", icon: "email"),
        TripReceipt(id: "swipe", kind: "CARD SWIPE", ref: "₹650 · café in Rishikesh · today — your food spend.", icon: "card"),
        TripReceipt(id: "search", kind: "SEARCH", ref: "“Kheerganga trek” ×2 · April — why I added Kasol.", icon: "search"),
        TripReceipt(id: "maps", kind: "HEALTH + MAPS", ref: "Located in Rishikesh · 11.4k steps today.", icon: "health"),
    ]

    // ── Build steps (the provenance chain) ───────────────────────────
    static let buildSteps: [BuildStep] = [
        BuildStep(id: "b1", src: "GMAIL · 18 MAY", text: "One email — your **round-trip into Delhi, out of Chandigarh.** That was all I had.", inferred: false),
        BuildStep(id: "b2", src: "INFERENCE", text: "Two cities, twelve days. I drew the **obvious hill route** between them — Nainital, Rishikesh.", inferred: true),
        BuildStep(id: "b3", src: "SEARCH · APRIL", text: "Your **“Kheerganga trek” searches** told me where you really wanted to go. I added Kasol.", inferred: true),
        BuildStep(id: "b4", src: "MAPS + HEALTH · LIVE", text: "Now I just **watch** — you’re in Rishikesh, day 5, 11.4k steps in.", inferred: false),
    ]

    // ── Corrections (README §A) ──────────────────────────────────────
    //
    // Keyed by LEG id (== the server leg ids). Every PAST leg carries a correction
    // so its pencil is never a dead control: the Delhi→Nainital fix is the seeded-
    // wrong scripted one (full spend reconcile); the Nainital→Rishikesh leg gets a
    // generic correction that still rewrites + teaches via the server's generic
    // fallback branch.
    static let corrections: [Correction] = [
        Correction(
            id: "c-leg-nainital", targetId: "leg-nainital",
            assumed: "I assumed you flew to Pantnagar — ₹4,900.",
            options: [
                .init(id: "bus", label: "Overnight Volvo bus"),
                .init(id: "cab", label: "Shared cab"),
                .init(id: "train", label: "Train via Kathgodam"),
            ],
            freeTextPlaceholder: "…or tell me in your own words."
        ),
        Correction(
            id: "c-leg-rishikesh", targetId: "leg-rishikesh",
            assumed: "I have this as the drive down via Kathgodam — ₹3,200.",
            options: [
                .init(id: "bus", label: "Overnight Volvo bus"),
                .init(id: "train", label: "Train + cab"),
                .init(id: "cab", label: "Shared cab"),
            ],
            freeTextPlaceholder: "…or tell me in your own words."
        ),
    ]

    // ── The assembled trip ───────────────────────────────────────────
    static let northIndia = Trip(
        id: "north",
        title: "North India",
        dateRange: "May 30 – Jun 11 | Nainital · Rishikesh · Kasol",
        meta: "opened this thread · 1 source",
        framing: "You forwarded one flight confirmation — Delhi in, Chandigarh out. I inferred the rest: five stops, twelve days. You're on day 5, in Rishikesh, and two legs still aren't booked.",
        framingAccent: "day 5",
        stops: stops, legs: legs, spend: spend,
        recommendations: recommendations, tracking: tracking,
        connectors: connectors, receipts: receipts,
        buildSteps: buildSteps, corrections: corrections
    )

    // ── Correction reconcile (MIRRORS the server) ────────────────────
    //
    // The reconcile rules below are a BYTE-FOR-BYTE mirror of the server's
    // `ruleForNainital` (src/server/routers/trip.ts): the same chosen mode,
    // the same fare in rupees, the same spend delta (so the offline total
    // matches the server's recompute exactly), and the same `changed` /
    // `learned` copy. Keeping them in lockstep means the optimistic offline
    // estimate settles to the SAME value the server returns — the leg + spend
    // never visibly jump when the `.server` path is on.

    /// The reconciled outcome for a correction answer — mirrors the server's
    /// `CorrectionRule` for the fields the iOS view needs (mode, fare, spend).
    struct ReconcileRule {
        let mode: String
        let fareRupees: Int
        /// Signed adjustment to the spend total (server: sum of segmentDelta).
        let totalDelta: Int
        let changed: (_ newTotal: Int) -> String
        let learned: String
    }

    /// Match a chip/free-text answer to a reconcile rule for the seeded-wrong
    /// Delhi→Nainital flight leg — mirror of the server's `ruleForNainital`. The
    /// base seed has that leg counted as a ₹4,900 flight; every ground option
    /// pulls it out of `flights` and books a smaller `travel` fare instead.
    static func ruleForNainital(answer: String) -> ReconcileRule {
        let a = answer.lowercased()
        if a.contains("cab") || a.contains("taxi") || a.contains("car") {
            return ReconcileRule(
                mode: "Shared cab via Kathgodam", fareRupees: 2_400,
                totalDelta: -4_900 + 2_400,
                changed: { "Nainital leg is a shared cab now, not a flight — spend is \(formatFare($0))." },
                learned: "You'd rather drive the first leg than fly it — I'll price cabs first up here.")
        }
        if a.contains("train") || a.contains("rail") || a.contains("kathgodam") {
            return ReconcileRule(
                mode: "Train to Kathgodam, cab up", fareRupees: 1_450,
                totalDelta: -4_900 + 1_450,
                changed: { "Nainital leg is the Kathgodam train now, not a flight — spend is \(formatFare($0))." },
                learned: "You took the train, not the flight — I'll lead with rail on legs like this.")
        }
        // Default + explicit bus/Volvo: the canonical "no, I took the bus".
        return ReconcileRule(
            mode: "Overnight Volvo bus", fareRupees: 1_150,
            totalDelta: -4_900 + 1_150,
            changed: { "Nainital leg is an overnight bus now, not a flight — spend dropped to \(formatFare($0))." },
            learned: "You chose the bus over the flight — I'll lead with sleepers on your Kasol leg too.")
    }

    /// The reconciled outcome for a leg id + answer, or nil for the generic
    /// fallback (any past leg other than the scripted Delhi→Nainital flight) —
    /// mirror of the server's `ruleFor`.
    static func rule(legId: String, answer: String) -> ReconcileRule? {
        legId == "leg-nainital" ? ruleForNainital(answer: answer) : nil
    }

    /// 4900 → "₹4,900" — mirror of the server's `formatFare` (en-IN grouping).
    static func formatFare(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.locale = Locale(identifier: "en_IN")
        return "₹" + (f.string(from: NSNumber(value: n)) ?? "\(n)")
    }

    /// Map a correction answer to its reconciled ripple (README §A) — mirror of
    /// the server's two branches. The seeded Delhi→Nainital fix is the SCRIPTED
    /// one (rewrite + spend recompute + a learned preference that tunes the NEXT
    /// suggestion); any other past leg takes the GENERIC branch (rewrite + teach,
    /// no scripted spend shift).
    static func reconcile(legId: String, answer: String) -> Ripple {
        if let r = rule(legId: legId, answer: answer) {
            let newTotal = spend.total + r.totalDelta
            return Ripple(changed: r.changed(newTotal), learned: r.learned)
        }
        // Generic branch — mirror of the server fallback: record the words, no
        // scripted spend shift.
        return Ripple(
            changed: "Updated — I've taken that on board.",
            learned: "Noted — I'll remember that: \(answer)."
        )
    }
}

// MARK: - Sync engine constants & id parity

/// Shared sync constants + id-parity helpers (SERVER_ARCHITECTURE.md §4.d). Kept
/// byte-compatible with `src/server/routers/sync.ts` (`canonicalId`,
/// `linkSyncKey`, the table registry, `MAX_PAGE`).
enum SyncEngine {
    /// The synced tables, in the server's registry order. `chapter_links` keys on
    /// the synthetic triple; everything else on `id`.
    static let tables: [String] = [
        "chapters", "todos", "decisions", "entries",
        "briefs", "watchers", "signals", "proposals", "chapter_links",
        "turns",
    ]

    /// Matches the server's `MAX_PAGE`.
    static let pageLimit = 500

    /// Drop a write-through after this many failed replays (poison-pill guard).
    static let outboxMaxAttempts = 6

    /// Canonical id form shared by both sides (§4.d): lowercase text-UUID.
    static func canonicalId(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Synthetic sync key for `chapter_links`: `from|to|relation`, canonical —
    /// byte-identical to the server's `linkSyncKey`.
    static func linkSyncKey(fromId: String, toId: String, relation: String) -> String {
        "\(canonicalId(fromId))|\(canonicalId(toId))|\(relation)"
    }

    /// A stable `UUID` for an `OutboxItem.clientRef` of a calendar push, derived
    /// from `(source, externalId)` so repeated foreground pushes of one event
    /// collapse to one queued item.
    static func calendarClientRef(externalId: String) -> UUID {
        deterministicUUID("calendar|\(externalId)")
    }

    /// A deterministic UUID derived from a string key (SHA-256 → first 16 bytes,
    /// stamped to RFC-4122 v5 layout). Used to give `chapter_links` and
    /// idempotent outbox items a stable local id without a server round-trip.
    static func deterministicUUID(_ key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Inverse used by tombstone application: recompute the link's local id from
    /// its sync key.
    static func uuidForLinkSyncKey(_ syncKey: String) -> UUID? {
        deterministicUUID(syncKey)
    }
}

/// An empty JSON object Encodable, used to seed a `@Model` blob field before the
/// delta upsert overwrites it from the server value.
private struct EmptyJSON: Encodable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode([String: String]())
    }
}
