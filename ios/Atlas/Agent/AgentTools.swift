import Foundation
import SwiftData
import os

/// AgentTools — all the read + write tools the agent loop can call. Each
/// tool captures a ModelContext (and sometimes a chapter scope) at
/// construction time, then exposes the AgentTool protocol so the Gemini
/// dispatch loop can call it generically.
///
/// The set mirrors the v0.2 brief's tool list, adapted for in-app SwiftData
/// instead of Postgres + external services:
///   chapter_query, chapter_details, brief_history, person_lookup,
///   calendar_query, gmail_search, note_to_self, web_search, web_fetch,
///   create_brief, create_proposal, create_watcher.
///
/// Web tools are best-effort stubs — they hit DuckDuckGo HTML and parse
/// what's there. If the user's network is offline the agent gets an error
/// payload and continues without that grounding.
enum AgentTools {

    /// Build the registry for a single event run.
    static func registry(for ctx: ModelContext, scopeChapter: Chapter? = nil) -> ToolRegistry {
        var r = ToolRegistry()
        r.register(ChapterQueryTool(ctx: ctx))
        r.register(ChapterDetailsTool(ctx: ctx))
        r.register(BriefHistoryTool(ctx: ctx))
        r.register(PersonLookupTool(ctx: ctx))
        r.register(CalendarQueryTool(ctx: ctx))
        r.register(GmailSearchTool(ctx: ctx))
        r.register(NoteToSelfTool(ctx: ctx, scopeChapter: scopeChapter))
        r.register(WebSearchTool())
        r.register(WebFetchTool())
        r.register(CreateBriefTool(ctx: ctx, scopeChapter: scopeChapter))
        r.register(CreateProposalTool(ctx: ctx, scopeChapter: scopeChapter))
        r.register(CreateWatcherTool(ctx: ctx, scopeChapter: scopeChapter))
        return r
    }
}

// MARK: - Schemas

private func obj(_ props: [String: [String: Any]], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": props
    ]
    if !required.isEmpty { schema["required"] = required }
    return schema
}
private func str(_ desc: String) -> [String: Any] { ["type": "string", "description": desc] }
private func int(_ desc: String) -> [String: Any] { ["type": "integer", "description": desc] }
private func num(_ desc: String) -> [String: Any] { ["type": "number", "description": desc] }
private func bool(_ desc: String) -> [String: Any] { ["type": "boolean", "description": desc] }
private func arrStr(_ desc: String) -> [String: Any] { ["type": "array", "description": desc, "items": ["type": "string"]] }

/// Lookup a Chapter by UUID string with a single fetch (predicate + limit 1).
/// Returns nil if the arg is missing/malformed or the chapter doesn't exist.
private func lookupChapter(_ raw: Any?, in ctx: ModelContext) -> Chapter? {
    guard let idStr = raw as? String, let id = UUID(uuidString: idStr) else { return nil }
    var descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try? ctx.fetch(descriptor).first
}

/// Accept either a serialised JSON string OR a raw dict/array as input. We
/// declare nested arg fields like `payload` as plain strings in the schema
/// (Gemini handles those most reliably across model versions) — but if the
/// model decides to emit a typed object instead, we still want to accept it.
private func decodeJSONArg(_ raw: Any?) -> Any? {
    guard let raw else { return nil }
    if let dict = raw as? [String: Any] { return dict }
    if let arr = raw as? [Any] { return arr }
    if let s = raw as? String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return parsed
    }
    return nil
}

// MARK: - Read tools

struct ChapterQueryTool: AgentTool {
    let ctx: ModelContext
    var name: String { "chapter_query" }
    var description: String { "List Ayumi's chapters. By default returns active + upcoming chapters only (the user's current world). Pass `include_done: true` if you need archived ones." }
    var parameters: [String: Any] {
        obj([
            "status":       str("Optional status filter (active / upcoming / paused / done)."),
            "type":         str("Optional chapter type filter."),
            "include_done": bool("If true, include done/paused chapters in the result (default: false).")
        ])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        let status = args["status"] as? String
        let type = args["type"] as? String
        let includeDone = (args["include_done"] as? Bool) ?? false
        // Sort active first, then upcoming, then others — gives the agent the
        // most-relevant chapters first when context window is tight.
        var descriptor = FetchDescriptor<Chapter>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60   // hard cap so a 200-chapter user doesn't blow the prompt
        let chapters = try ctx.fetch(descriptor)
        let iso = ISO8601DateFormatter()   // one per call — formatters aren't thread-safe
        var out: [[String: Any]] = []
        for c in chapters {
            if let s = status, c.statusRaw != s { continue }
            if let t = type, c.typeRaw != t { continue }
            if !includeDone && (c.statusRaw == "done" || c.statusRaw == "paused") { continue }
            out.append([
                "id": c.id.uuidString,
                "title": c.title,
                "type": c.typeRaw,
                "status": c.statusRaw,
                "purpose": c.purpose ?? "",
                "open_todos": c.openTodos.count,
                "done_todos": c.doneTodos.count,
                "start_date": c.startDate.map { iso.string(from: $0) } ?? "",
                "end_date":   c.endDate.map   { iso.string(from: $0) } ?? ""
            ])
        }
        return .ok(["chapters": out, "count": out.count])
    }
}

struct ChapterDetailsTool: AgentTool {
    let ctx: ModelContext
    var name: String { "chapter_details" }
    var description: String { "Full contents of a chapter — todos, decisions, journal entries, links." }
    var parameters: [String: Any] {
        obj(["chapter_id": str("Chapter UUID from chapter_query.")], required: ["chapter_id"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let idStr = args["chapter_id"] as? String, let id = UUID(uuidString: idStr) else {
            return .error("missing or malformed chapter_id")
        }
        var descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let c = try ctx.fetch(descriptor).first else {
            return .error("no chapter with id \(idStr)")
        }
        let todos = c.todos.sorted { $0.createdAt < $1.createdAt }.map {
            [
                "text": $0.text,
                "done": $0.done,
                "source": $0.sourceRaw,
                "due": $0.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            ] as [String: Any]
        }
        let decisions = c.decisions.sorted { $0.decidedAt < $1.decidedAt }.map {
            [
                "title": $0.title,
                "rationale": $0.rationale ?? "",
                "decided_at": ISO8601DateFormatter().string(from: $0.decidedAt)
            ] as [String: Any]
        }
        let entries = c.entries.sorted { $0.date > $1.date }.prefix(10).map {
            [
                "date": ISO8601DateFormatter().string(from: $0.date),
                "content": $0.content,
                "source": $0.sourceRaw
            ] as [String: Any]
        }
        return .ok([
            "title": c.title,
            "type": c.typeRaw,
            "status": c.statusRaw,
            "purpose": c.purpose ?? "",
            "todos": todos,
            "decisions": decisions,
            "entries": Array(entries)
        ])
    }
}

struct BriefHistoryTool: AgentTool {
    let ctx: ModelContext
    var name: String { "brief_history" }
    var description: String { "Prior briefs that Atlas has drafted for a chapter, newest first." }
    var parameters: [String: Any] {
        obj([
            "chapter_id": str("Chapter UUID — optional. If omitted, returns recent briefs across all chapters."),
            "limit": int("Max briefs to return (default 5).")
        ])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        let limit = max(1, min((args["limit"] as? Int) ?? 5, 25))
        var descriptor = FetchDescriptor<Brief>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Bound the fetch so a 500-brief history doesn't pull the whole table
        // into memory on every tool call. If a chapter filter is requested we
        // fetch a small multiple and filter in memory (rare path).
        let chapterFilter: UUID? = (args["chapter_id"] as? String).flatMap(UUID.init(uuidString:))
        descriptor.fetchLimit = chapterFilter == nil ? limit : limit * 4
        var briefs = try ctx.fetch(descriptor)
        if let id = chapterFilter {
            briefs = briefs.filter { $0.chapter?.id == id }
        }
        let slim = briefs.prefix(limit).map { b -> [String: Any] in
            [
                "id": b.id.uuidString,
                "title": b.title,
                "situation": b.situationDescription,
                "drafted_at": ISO8601DateFormatter().string(from: b.createdAt),
                "status": b.statusRaw,
                "chapter": b.chapterTitle ?? ""
            ]
        }
        return .ok(["briefs": Array(slim), "count": slim.count])
    }
}

struct PersonLookupTool: AgentTool {
    let ctx: ModelContext
    var name: String { "person_lookup" }
    var description: String { "Find what Atlas knows about a person — searches signal summaries and chapter contents for the name or email." }
    var parameters: [String: Any] {
        obj(["query": str("Name or email to search for.")], required: ["query"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let q = (args["query"] as? String)?.lowercased(), !q.isEmpty else {
            return .error("missing query")
        }
        // Limit the signal scan to the most-recent 200 — enough for most
        // person searches without dragging the entire signals table into RAM.
        var sigDesc = FetchDescriptor<Signal>(
            sortBy: [SortDescriptor(\.arrivedAt, order: .reverse)]
        )
        sigDesc.fetchLimit = 200
        let signals = try ctx.fetch(sigDesc)
        let matches = signals.filter { ($0.summary ?? "").lowercased().contains(q) || ($0.externalId ?? "").lowercased().contains(q) }
        let iso = ISO8601DateFormatter()
        let signalHits = matches.prefix(8).map { s -> [String: Any] in
            [
                "source": s.sourceRaw,
                "arrived_at": iso.string(from: s.arrivedAt),
                "summary": s.summary ?? "",
                "external_id": s.externalId ?? ""
            ]
        }
        // Chapter scan stays in-memory: chapters are small (~tens) and we
        // need the relationships expanded anyway.
        let chapters = try ctx.fetch(FetchDescriptor<Chapter>())
        var chapterHits: [[String: Any]] = []
        for c in chapters {
            let inDecisions = c.decisions.contains { ($0.rationale ?? "").lowercased().contains(q) || $0.title.lowercased().contains(q) }
            let inEntries   = c.entries.contains { $0.content.lowercased().contains(q) }
            if inDecisions || inEntries {
                chapterHits.append(["chapter": c.title, "in_decisions": inDecisions, "in_entries": inEntries])
            }
        }
        return .ok(["signals": Array(signalHits), "chapters": chapterHits, "count": signalHits.count + chapterHits.count])
    }
}

struct CalendarQueryTool: AgentTool {
    let ctx: ModelContext
    var name: String { "calendar_query" }
    var description: String { "Calendar events between two ISO-8601 timestamps, drawn from signals where source=calendar." }
    var parameters: [String: Any] {
        obj([
            "start": str("ISO-8601 start timestamp, inclusive."),
            "end":   str("ISO-8601 end timestamp, inclusive.")
        ], required: ["start", "end"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        let iso = ISO8601DateFormatter()
        guard let s = args["start"] as? String, let e = args["end"] as? String,
              let start = iso.date(from: s) ?? AtlasFormat.iso.date(from: s),
              let end = iso.date(from: e) ?? AtlasFormat.iso.date(from: e) else {
            return .error("start and end must be ISO-8601 timestamps")
        }
        let calRaw = SignalSource.calendar.rawValue
        var descriptor = FetchDescriptor<Signal>(
            predicate: #Predicate { $0.sourceRaw == calRaw && $0.arrivedAt >= start && $0.arrivedAt <= end },
            sortBy: [SortDescriptor(\.arrivedAt, order: .forward)]
        )
        descriptor.fetchLimit = 50
        let inRange = try ctx.fetch(descriptor)
        let out = inRange.map { s -> [String: Any] in
            var dict: [String: Any] = [
                "arrived_at": iso.string(from: s.arrivedAt),
                "summary": s.summary ?? "",
                "external_id": s.externalId ?? ""
            ]
            if let raw = try? JSONSerialization.jsonObject(with: s.rawDataJSON) {
                dict["raw"] = raw
            }
            return dict
        }
        return .ok(["events": out, "count": out.count])
    }
}

struct GmailSearchTool: AgentTool {
    let ctx: ModelContext
    var name: String { "gmail_search" }
    var description: String { "Search gmail signals by a free-text query in the summary or address. Returns up to 10 matches." }
    var parameters: [String: Any] {
        obj([
            "query": str("Substring to match against the summary or external_id."),
            "since": str("Optional ISO-8601 lower bound for arrival time.")
        ], required: ["query"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let q = (args["query"] as? String)?.lowercased(), !q.isEmpty else {
            return .error("missing query")
        }
        let since = (args["since"] as? String).flatMap(ISO8601DateFormatter().date(from:))
        let gmailRaw = SignalSource.gmail.rawValue
        // Predicate-filter by source and (when given) arrival floor — keeps
        // the in-memory string-match scan small.
        var descriptor: FetchDescriptor<Signal>
        if let since {
            descriptor = FetchDescriptor<Signal>(
                predicate: #Predicate { $0.sourceRaw == gmailRaw && $0.arrivedAt >= since },
                sortBy: [SortDescriptor(\.arrivedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<Signal>(
                predicate: #Predicate { $0.sourceRaw == gmailRaw },
                sortBy: [SortDescriptor(\.arrivedAt, order: .reverse)]
            )
        }
        descriptor.fetchLimit = 200    // bound the working set
        let sigs = try ctx.fetch(descriptor)
        let matches = sigs.filter { ($0.summary ?? "").lowercased().contains(q) || ($0.externalId ?? "").lowercased().contains(q) }
        let iso = ISO8601DateFormatter()
        let out = matches.prefix(10).map { s -> [String: Any] in
            [
                "arrived_at": iso.string(from: s.arrivedAt),
                "summary": s.summary ?? "",
                "external_id": s.externalId ?? ""
            ]
        }
        return .ok(["messages": Array(out), "count": out.count])
    }
}

// MARK: - Web tools (best-effort, stub-friendly)

struct WebSearchTool: AgentTool {
    var name: String { "web_search" }
    var description: String { "Public web search via DuckDuckGo. Returns the top 5 titles + snippets." }
    var parameters: [String: Any] {
        obj(["query": str("Search query.")], required: ["query"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let q = args["query"] as? String, !q.isEmpty else { return .error("missing query") }
        // Best-effort: use the DuckDuckGo HTML endpoint and pull a few <a>'s.
        var components = URLComponents(string: "https://duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = components.url else { return .error("malformed query") }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 Atlas/0.2", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            let results = extractDDGResults(html: html, limit: 5)
            return .ok(["results": results, "query": q])
        } catch {
            // Fall back: tell the agent we couldn't reach the web so it
            // doesn't keep retrying. Atlas can use its memory instead.
            return .ok(["results": [], "query": q, "note": "web unreachable: \(error.localizedDescription)"])
        }
    }

    private func extractDDGResults(html: String, limit: Int) -> [[String: Any]] {
        var out: [[String: Any]] = []
        let pattern = #"result__a"\s+[^>]*href="([^"]+)"[^>]*>(.+?)</a>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return out }
        let ns = html as NSString
        re.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, out.count < limit, m.numberOfRanges >= 3 else { return }
            let href = ns.substring(with: m.range(at: 1))
            let raw = ns.substring(with: m.range(at: 2))
            let title = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            out.append(["url": href, "title": title])
            if out.count >= limit { stop.pointee = true }
        }
        return out
    }
}

struct WebFetchTool: AgentTool {
    var name: String { "web_fetch" }
    var description: String { "Fetch a URL and return the first ~6KB of text content, with HTML tags stripped." }
    var parameters: [String: Any] {
        obj(["url": str("URL to fetch.")], required: ["url"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let s = args["url"] as? String, let url = URL(string: s) else { return .error("missing or malformed url") }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 Atlas/0.2", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let raw = String(data: data, encoding: .utf8) ?? ""
            let stripped = raw.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let snippet = String(stripped.prefix(6000))
            return .ok(["url": s, "status": http?.statusCode ?? 0, "text": snippet, "bytes": data.count])
        } catch {
            return .error("fetch failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Write tools

struct NoteToSelfTool: AgentTool {
    let ctx: ModelContext
    let scopeChapter: Chapter?
    var name: String { "note_to_self" }
    var description: String { "Leave a low-priority watcher for yourself to revisit later. Writes a Watcher with internal source." }
    var parameters: [String: Any] {
        obj([
            "description": str("Human-readable label, e.g. 'check whether deck v3 reached Karan'."),
            "prompt": str("What to look for when this watcher fires."),
            "minutes_until_check": int("How many minutes from now to recheck (default 1440 = 1 day).")
        ], required: ["description", "prompt"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let desc = args["description"] as? String, let prompt = args["prompt"] as? String else {
            return .error("missing description or prompt")
        }
        let mins = (args["minutes_until_check"] as? Int) ?? (24 * 60)
        let w = Watcher(
            watcherDescription: desc,
            prompt: prompt,
            sourceType: .internalSource,
            nextCheck: Date().addingTimeInterval(TimeInterval(mins * 60)),
            cadenceMinutes: mins,
            cadenceLabel: mins >= 60 * 24 ? "daily" : "in \(mins)m",
            chapter: scopeChapter
        )
        ctx.insert(w)
        do { try ctx.save() } catch { return .error("save failed: \(error.localizedDescription)") }
        return .ok(["watcher_id": w.id.uuidString, "description": desc])
    }
}

struct CreateBriefTool: AgentTool {
    let ctx: ModelContext
    let scopeChapter: Chapter?
    var name: String { "create_brief" }
    var description: String { "Write a Brief — the unit of value. Composes UI sections from the library and surfaces it on Today." }
    var parameters: [String: Any] {
        obj([
            "title": str("Serif-italic title shown on the brief card (e.g. 'Karan, in 90 minutes')."),
            "situation": str("One-sentence description of what you understood the situation to be."),
            // `structure` is declared as a string so Gemini reliably returns
            // a serialised JSON document — wrapping it as a typed object with
            // dynamic property names broke first-run dispatch (Gemini either
            // emitted an empty {} or stringified the dict). We parse the JSON
            // ourselves below. Same approach as create_proposal.payload.
            "structure": str("JSON string for a BriefStructure: {\"sections\":[{\"kind\":\"person|timeline|prediction|materials|options|tactical|quote|watcher|diff|action\",\"data\":{...}}]}. Use only the kinds listed in the system prompt."),
            "chapter_id": str("Optional chapter UUID to attach this brief to."),
            "chapter_title": str("Cached chapter title (for the teaser card)."),
            "relevance": str("Short editorial tag (e.g. 'partner intro · second touch')."),
            "when": str("Editorial when string (e.g. 'today · 14:30')."),
            "preview": str("One-line preview shown in the teaser card."),
            "primary_action": str("Label for the primary footer button."),
            "secondary_actions": arrStr("Optional secondary action labels.")
        ], required: ["title", "situation", "structure"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let title = args["title"] as? String,
              let situation = args["situation"] as? String else {
            return .error("missing title or situation")
        }
        // Accept either a serialised JSON string (preferred per schema) or a
        // raw dict (in case Gemini falls back to typed object emission).
        guard let structureDict = decodeJSONArg(args["structure"]) as? [String: Any] else {
            return .error("missing or malformed structure (expected JSON string of BriefStructure)")
        }
        let structureData = (try? JSONSerialization.data(withJSONObject: structureDict)) ?? Data()
        let chapter: Chapter? = lookupChapter(args["chapter_id"], in: ctx) ?? scopeChapter
        let brief = Brief(
            title: title,
            situationDescription: situation,
            structureData: structureData,
            status: .surfaced,
            surfaceAt: Date(),
            chapter: chapter,
            chapterTitle: args["chapter_title"] as? String ?? chapter?.title,
            relevance: args["relevance"] as? String,
            when: args["when"] as? String,
            drafted: AtlasFormat.briefDraftedStamp(Date()),
            preview: args["preview"] as? String,
            primaryAction: args["primary_action"] as? String,
            secondaryActions: args["secondary_actions"] as? [String]
        )
        ctx.insert(brief)
        do { try ctx.save() } catch { return .error("save failed: \(error.localizedDescription)") }
        return .ok(["brief_id": brief.id.uuidString, "title": title])
    }
}

struct CreateProposalTool: AgentTool {
    let ctx: ModelContext
    let scopeChapter: Chapter?
    var name: String { "create_proposal" }
    var description: String { "Propose a todo / decision / journal entry / chapter / chapter_link for the user to approve. Goes into the Review queue." }
    var parameters: [String: Any] {
        obj([
            "type": str("One of: todo, decision, journal_entry, chapter, chapter_link."),
            // Declared as a JSON string so Gemini reliably emits it without
            // needing dynamic typed-object schemas. We parse below.
            "payload": str("JSON string. Shape depends on type. todo: {\"text\":\"...\",\"due\":\"ISO-8601 optional\"}. decision: {\"title\":\"...\",\"rationale\":\"...\"}. journal_entry: {\"content\":\"...\"}. chapter: {\"title\":\"...\",\"type\":\"trip|move|project|launch|recurring|personal\",\"purpose\":\"...\"}. chapter_link: {\"from_chapter_id\":\"uuid\",\"to_chapter_id\":\"uuid\",\"relation\":\"blocks|enables|conflicts|related\"}."),
            "confidence": num("Your confidence in this proposal, 0.0–1.0."),
            "reasoning": str("Short justification for the user (not shown by default)."),
            "summary": str("One-line summary for the Review row."),
            "chapter_id": str("Optional chapter UUID to attach to."),
            "source_label": str("Where this came from (e.g. 'Email', 'Voice memo', 'Inferred')."),
            "source_meta": str("Inline source meta (e.g. 'from karan@... · 06:12')."),
            "question": str("Optional — turns this into an 'asked' proposal. The user picks between two options."),
            "setup": str("Optional — context sentence for the asked proposal."),
            "options": [
                "type": "array",
                "description": "Optional — two-element list of { label, value, result, type } if this is an asked proposal.",
                "items": [
                    "type": "object",
                    "properties": [
                        "label": ["type": "string"],
                        "value": ["type": "string"],
                        "result": ["type": "string"],
                        "type": ["type": "string"]
                    ]
                ]
            ]
        ], required: ["type", "payload", "confidence", "summary"])
    }

    private struct GenericPayload: Encodable {
        let dict: [String: Any]
        func encode(to encoder: Encoder) throws {
            let data = try JSONSerialization.data(withJSONObject: dict)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            try any.encode(to: encoder)
        }
    }

    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let typeStr = args["type"] as? String, let type = ProposalType(rawValue: typeStr) else {
            return .error("unknown proposal type")
        }
        guard let payload = decodeJSONArg(args["payload"]) as? [String: Any] else {
            return .error("missing or malformed payload (expected JSON string)")
        }
        let confidence = (args["confidence"] as? Double) ?? (args["confidence"] as? NSNumber)?.doubleValue ?? 0.5
        let chapter: Chapter? = lookupChapter(args["chapter_id"], in: ctx) ?? scopeChapter
        let optsRaw = args["options"] as? [[String: Any]]
        let options = optsRaw?.compactMap { o -> ProposalOption? in
            guard let l = o["label"] as? String, let v = o["value"] as? String else { return nil }
            return ProposalOption(label: l, value: v, result: o["result"] as? String, type: o["type"] as? String)
        }

        let p = Proposal(
            type: type,
            proposedPayload: GenericPayload(dict: payload),
            confidence: confidence,
            chapter: chapter,
            status: .pending,
            summary: args["summary"] as? String,
            sourceLabel: args["source_label"] as? String,
            sourceMeta: args["source_meta"] as? String,
            question: args["question"] as? String,
            setup: args["setup"] as? String,
            options: options,
            reasoning: args["reasoning"] as? String
        )
        ctx.insert(p)
        do { try ctx.save() } catch { return .error("save failed: \(error.localizedDescription)") }
        return .ok(["proposal_id": p.id.uuidString, "type": typeStr])
    }
}

struct CreateWatcherTool: AgentTool {
    let ctx: ModelContext
    let scopeChapter: Chapter?
    var name: String { "create_watcher" }
    var description: String { "Add a standing instruction for Atlas to recheck on a cadence." }
    var parameters: [String: Any] {
        obj([
            "description": str("Human-readable label (e.g. 'VFS appointment slots before Jun 28')."),
            "prompt": str("What you should look for when this watcher fires."),
            "source_type": str("One of: web, gmail, calendar, drive, internal."),
            "cadence_minutes": int("How often to recheck (default 180 = every 3 hours)."),
            "chapter_id": str("Optional chapter UUID to attach to.")
        ], required: ["description", "prompt", "source_type"])
    }
    func dispatch(args: [String: Any]) async throws -> ToolResult {
        guard let desc = args["description"] as? String,
              let prompt = args["prompt"] as? String,
              let stRaw = args["source_type"] as? String,
              let st = WatcherSourceType(rawValue: stRaw) else {
            return .error("missing description / prompt / valid source_type")
        }
        let mins = (args["cadence_minutes"] as? Int) ?? 180
        let chapter: Chapter? = lookupChapter(args["chapter_id"], in: ctx) ?? scopeChapter
        let cadenceLabel: String = {
            switch mins {
            case ...60:        return "hourly"
            case ...180:       return "every 3h"
            case ...360:       return "every 6h"
            case ...(60 * 24): return "daily"
            default:           return "weekly"
            }
        }()
        let w = Watcher(
            watcherDescription: desc,
            prompt: prompt,
            sourceType: st,
            nextCheck: Date().addingTimeInterval(TimeInterval(mins * 60)),
            cadenceMinutes: mins,
            cadenceLabel: cadenceLabel,
            chapter: chapter
        )
        ctx.insert(w)
        do { try ctx.save() } catch { return .error("save failed: \(error.localizedDescription)") }
        return .ok(["watcher_id": w.id.uuidString, "description": desc])
    }
}

// MARK: - AnyCodable for arbitrary JSON payloads

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = NSNull() }
        else if let b = try? c.decode(Bool.self)     { self.value = b }
        else if let i = try? c.decode(Int.self)      { self.value = i }
        else if let d = try? c.decode(Double.self)   { self.value = d }
        else if let s = try? c.decode(String.self)   { self.value = s }
        else if let a = try? c.decode([AnyCodable].self) { self.value = a.map(\.value) }
        else if let o = try? c.decode([String: AnyCodable].self) {
            self.value = o.mapValues(\.value)
        }
        else { self.value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:           try c.encodeNil()
        case let b as Bool:       try c.encode(b)
        case let i as Int:        try c.encode(i)
        case let d as Double:     try c.encode(d)
        case let s as String:     try c.encode(s)
        case let a as [Any]:      try c.encode(a.map(AnyCodable.init))
        case let o as [String: Any]: try c.encode(o.mapValues(AnyCodable.init))
        default:
            try c.encodeNil()
        }
    }
}

// MARK: - Formatter helper

extension AtlasFormat {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func briefDraftedStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "drafted \(f.string(from: date))"
    }
}
