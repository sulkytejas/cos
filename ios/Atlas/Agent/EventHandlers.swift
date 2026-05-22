import Foundation
import SwiftData
import os

/// EventDispatcher — routes a pending AppEvent to the right handler. Each
/// handler is responsible for reading the payload, running an agent turn (or
/// doing direct work), and emitting any downstream Briefs / Proposals via
/// the tools.
enum EventDispatcher {
    static let log = Logger(subsystem: "com.atlas.app", category: "EventDispatcher")

    static func handle(event: AppEvent, ctx: ModelContext, agent: AtlasAgent) async throws {
        log.info("handling event \(event.id.uuidString, privacy: .public) type=\(event.typeRaw, privacy: .public)")
        switch event.type {
        case .captureReceived:
            try await CaptureHandler.handle(event: event, ctx: ctx)
        case .watcherDue:
            try await WatcherDueHandler.handle(event: event, ctx: ctx)
        case .dailyScan, .timeTrigger:
            try await TimeTriggerHandler.handle(event: event, ctx: ctx)
        case .signalReceived:
            try await SignalReceivedHandler.handle(event: event, ctx: ctx)
        case .briefActedOn:
            try await BriefActedOnHandler.handle(event: event, ctx: ctx)
        case .chapterCreated:
            try await ChapterCreatedHandler.handle(event: event, ctx: ctx)
        case .chapterUpdated:
            // Update events are noisy — could touch many fields. Don't run
            // the agent automatically. The daily scan picks up overdue work.
            log.info("chapter_updated noted, no agent action")
        }
    }
}

// MARK: - Chapter created handler

enum ChapterCreatedHandler {
    static let log = Logger(subsystem: "com.atlas.app", category: "ChapterCreatedHandler")

    static func handle(event: AppEvent, ctx: ModelContext) async throws {
        guard let payload = try? JSONDecoder().decode(ChapterCreatedPayload.self, from: event.payloadJSON) else {
            throw NSError(domain: "AtlasAgent", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "bad chapter_created payload"])
        }
        let targetID = payload.chapterID
        var descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let chapter = try ctx.fetch(descriptor).first else {
            log.info("chapter \(targetID.uuidString, privacy: .public) not found")
            return
        }
        guard UserDefaults.standard.string(forKey: "GeminiAPIKey")?.isEmpty == false else {
            log.info("no API key — skipping agent run for new chapter")
            return
        }

        let userText = """
        The user just created a new chapter:

        - Title: \(chapter.title)
        - Type: \(chapter.typeRaw)
        - Status: \(chapter.statusRaw)
        - Purpose: \(chapter.purpose ?? "(unspecified)")
        - Start: \(chapter.startDate.map { ISO8601DateFormatter().string(from: $0) } ?? "(none)")
        - End:   \(chapter.endDate.map { ISO8601DateFormatter().string(from: $0) } ?? "(none)")

        Propose 2–3 starter todos that get the chapter off the ground and \
        — if it fits the chapter's shape — one watcher for something Ayumi \
        should keep an eye on (gmail thread, web prices, calendar slot, etc).

        Use chapter_id "\(chapter.id.uuidString)" when calling create_proposal \
        and create_watcher so they attach to this chapter. Keep proposals \
        concrete and small — these are the first taps.
        """
        let registry = AgentTools.registry(for: ctx, scopeChapter: chapter)
        _ = try await GeminiAgent.run(userText: userText, tools: registry)
        log.info("chapter_created handled for \(chapter.title, privacy: .public)")
    }
}

// MARK: - Capture handler — the most common path

enum CaptureHandler {
    static let log = Logger(subsystem: "com.atlas.app", category: "CaptureHandler")

    static func handle(event: AppEvent, ctx: ModelContext) async throws {
        guard let payload = try? JSONDecoder().decode(CapturePayload.self, from: event.payloadJSON) else {
            throw NSError(domain: "AtlasAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad capture payload"])
        }
        let scopeChapter: Chapter? = {
            guard let cid = payload.chapterID else { return nil }
            return (try? ctx.fetch(FetchDescriptor<Chapter>()))?.first(where: { $0.id == cid })
        }()

        // If there's no API key, fall back to writing a manual proposal so the
        // capture isn't lost — same behaviour as the prior CaptureSheet.save().
        guard UserDefaults.standard.string(forKey: "GeminiAPIKey")?.isEmpty == false else {
            log.info("no API key — filing capture as a pending todo proposal")
            try fallbackPersistAsProposal(payload: payload, chapter: scopeChapter, ctx: ctx)
            return
        }

        let userText = """
        The user just captured this text:

        ---
        \(payload.text)
        ---

        Their suggested kind is `\(payload.kind)` and the chapter context is \
        `\(scopeChapter?.title ?? "unspecified")`.

        Use chapter_query and chapter_details to confirm context, then create \
        one or more proposals (todo / decision / journal_entry) for the user to \
        approve in the Review queue. If the capture suggests a situation worth \
        a brief (an upcoming meeting / trip / deadline), call create_brief too. \
        If something here should be rechecked later, call note_to_self or create_watcher.
        """

        let registry = AgentTools.registry(for: ctx, scopeChapter: scopeChapter)
        do {
            let result = try await GeminiAgent.run(userText: userText, tools: registry)
            log.info("capture handled — \(result.trace.count) trace steps, final text \(result.finalText.prefix(120), privacy: .public)")
        } catch {
            // Don't lose the capture — write a fallback proposal and rethrow so
            // the AppEvent is marked failed (the user still sees their text).
            try? fallbackPersistAsProposal(payload: payload, chapter: scopeChapter, ctx: ctx)
            throw error
        }
    }

    /// Used when the API isn't configured or the agent loop failed. Writes the
    /// captured text as a pending proposal so it surfaces in Review.
    private static func fallbackPersistAsProposal(payload: CapturePayload, chapter: Chapter?, ctx: ModelContext) throws {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let type: ProposalType = {
            switch payload.kind.lowercased() {
            case "decision":           return .decision
            case "journal", "entry":   return .journalEntry
            default:                   return .todo
            }
        }()
        let dict: [String: Any]
        switch type {
        case .decision:
            dict = ["title": String(trimmed.prefix(120)), "rationale": trimmed]
        case .journalEntry:
            dict = ["content": trimmed]
        default:
            dict = ["text": trimmed]
        }
        let p = Proposal(
            type: type,
            proposedPayload: GenericProposalPayload(dict: dict),
            confidence: 0.4,
            chapter: chapter,
            status: .pending,
            summary: "Captured: \(trimmed.prefix(80))",
            sourceLabel: "Capture",
            sourceMeta: AtlasFormat.shortDay.string(from: Date()),
            reasoning: "Filed without LLM — add a Gemini key in Settings to let Atlas reason about captures."
        )
        ctx.insert(p)
        try? ctx.save()
    }

    struct GenericProposalPayload: Encodable {
        let dict: [String: Any]
        func encode(to encoder: Encoder) throws {
            let any = AnyCodable(dict)
            try any.encode(to: encoder)
        }
    }
}

// MARK: - Watcher-due handler

enum WatcherDueHandler {
    static let log = Logger(subsystem: "com.atlas.app", category: "WatcherDueHandler")

    static func handle(event: AppEvent, ctx: ModelContext) async throws {
        guard let payload = try? JSONDecoder().decode(WatcherDuePayload.self, from: event.payloadJSON) else {
            throw NSError(domain: "AtlasAgent", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "bad watcher_due payload"])
        }
        let targetID = payload.watcherID
        var descriptor = FetchDescriptor<Watcher>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let watcher = try ctx.fetch(descriptor).first else {
            log.info("watcher \(targetID.uuidString, privacy: .public) not found")
            return
        }
        guard UserDefaults.standard.string(forKey: "GeminiAPIKey")?.isEmpty == false else {
            log.info("no API key — skipping watcher \(watcher.id.uuidString, privacy: .public)")
            return
        }

        let userText = """
        Watcher fired:

        - Description: \(watcher.watcherDescription)
        - Source: \(watcher.sourceTypeRaw)
        - Prompt: \(watcher.prompt)

        Recheck according to the prompt. Use the appropriate tool (web_search, \
        gmail_search, calendar_query, etc.) to look. If you find something \
        worth surfacing, call create_brief and/or create_proposal. If nothing \
        has changed, return a one-line summary so we can log it and move on.
        """
        let registry = AgentTools.registry(for: ctx, scopeChapter: watcher.chapter)
        let result = try await GeminiAgent.run(userText: userText, tools: registry)
        // Only mark lastChecked on a successful run, so a transient failure
        // doesn't silently lose the next check window.
        watcher.lastChecked = Date()
        let summary: [String: Any] = [
            "summary": String(result.finalText.prefix(400)),
            "checked_at": ISO8601DateFormatter().string(from: Date())
        ]
        watcher.lastFindingJSON = try? JSONSerialization.data(withJSONObject: summary)
        try ctx.save()
        log.info("watcher \(watcher.id.uuidString, privacy: .public) checked")
    }
}

// MARK: - Time-trigger / daily scan handler

enum TimeTriggerHandler {
    static let log = Logger(subsystem: "com.atlas.app", category: "TimeTriggerHandler")

    static func handle(event: AppEvent, ctx: ModelContext) async throws {
        let payload = try? JSONDecoder().decode(DailyScanPayload.self, from: event.payloadJSON)
        let forwardDrift = payload?.forwardDrift ?? false

        guard UserDefaults.standard.string(forKey: "GeminiAPIKey")?.isEmpty == false else {
            log.info("no API key — skipping daily scan")
            return
        }

        let userText: String
        if forwardDrift {
            userText = """
            It's Sunday morning IST. Run the forward-drift scan: look across \
            chapters for things drifting (overdue todos, decisions still open, \
            briefs that surfaced but were never acted on). Call chapter_query, \
            then chapter_details for the busiest ones, then brief_history to \
            see what's already been said. Propose one brief OR one summary \
            proposal at most — this is the weekly reflection, not a flood.
            """
        } else {
            userText = """
            It's 6am IST — daily scan time. Build the "Handled while you slept" \
            picture and the morning Briefs queue. Use chapter_query to see \
            what's active. For any chapter with a milestone in the next 3 days, \
            check brief_history and call create_brief if none has been drafted \
            in the last 18 hours. Keep proposals minimal — the user reads them \
            first thing.
            """
        }
        let registry = AgentTools.registry(for: ctx)
        let result = try await GeminiAgent.run(userText: userText, tools: registry)
        log.info("time-trigger handled, \(result.trace.count) steps")
    }
}

// MARK: - Signal received handler

enum SignalReceivedHandler {
    static let log = Logger(subsystem: "com.atlas.app", category: "SignalReceivedHandler")

    static func handle(event: AppEvent, ctx: ModelContext) async throws {
        guard let payload = try? JSONDecoder().decode(SignalReceivedPayload.self, from: event.payloadJSON) else {
            throw NSError(domain: "AtlasAgent", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "bad signal_received payload"])
        }
        // Predicate-fetch with limit 1 — much faster than fetching all signals.
        let targetID = payload.signalID
        var descriptor = FetchDescriptor<Signal>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let signal = try ctx.fetch(descriptor).first else {
            log.info("signal \(targetID.uuidString, privacy: .public) not found — already deleted?")
            return
        }
        guard UserDefaults.standard.string(forKey: "GeminiAPIKey")?.isEmpty == false else {
            signal.processed = true
            try ctx.save()
            return
        }

        let userText = """
        New signal arrived from \(signal.sourceRaw):

        - Summary: \(signal.summary ?? "(no summary)")
        - External id: \(signal.externalId ?? "(none)")

        Decide whether this signal is worth surfacing. If yes — call \
        create_proposal or create_brief. If no — just return one line saying \
        so. Use person_lookup and chapter_query to see if it fits a chapter.
        """
        let registry = AgentTools.registry(for: ctx)
        _ = try await GeminiAgent.run(userText: userText, tools: registry)
        signal.processed = true
        try ctx.save()
    }
}

// MARK: - Brief acted on handler

enum BriefActedOnHandler {
    static let log = Logger(subsystem: "com.atlas.app", category: "BriefActedOnHandler")

    static func handle(event: AppEvent, ctx: ModelContext) async throws {
        guard let payload = try? JSONDecoder().decode(BriefActedOnPayload.self, from: event.payloadJSON) else {
            return
        }
        let targetID = payload.briefID
        var descriptor = FetchDescriptor<Brief>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let brief = try ctx.fetch(descriptor).first else { return }
        switch payload.action {
        case "dismiss":   brief.status = .dismissed
        case "snooze":    brief.surfaceAt = Date().addingTimeInterval(3600)
        case "primary":   brief.status = .actedOn
        case "dig_deeper":
            // Queue a new agent run with the brief's situation as input.
            let userText = """
            The user asked Atlas to dig deeper on this brief:

            Title: \(brief.title)
            Situation: \(brief.situationDescription)

            Use web_search and brief_history to add depth. Propose a follow-up \
            brief OR a proposal that wasn't there before. Don't repeat what's \
            already in the brief.
            """
            let registry = AgentTools.registry(for: ctx, scopeChapter: brief.chapter)
            _ = try await GeminiAgent.run(userText: userText, tools: registry)
        default:
            break
        }
        try? ctx.save()
    }
}

// MARK: - Connectors — stub Gmail / Calendar / Drive

/// ConnectorRunner — invoked every 15 minutes from AtlasAgent.tickOnce. Each
/// connector reads from a bundled fixture (compiled into Swift here, no
/// resource registration needed) and writes new Signals.
enum ConnectorRunner {
    static let log = Logger(subsystem: "com.atlas.app", category: "Connectors")

    static func pollOnce(in ctx: ModelContext) {
        GmailConnector.pollOnce(ctx: ctx)
        CalendarConnector.pollOnce(ctx: ctx)
        DriveConnector.pollOnce(ctx: ctx)
    }
}

enum GmailConnector {
    /// Idempotent — uses externalId as a unique key so re-polls don't dupe.
    /// For each newly-inserted Signal, also enqueues a `signal_received`
    /// AppEvent so the agent gets a chance to react in real time (without
    /// this, signals only got picked up by the daily scan).
    static func pollOnce(ctx: ModelContext) {
        let gmailRaw = SignalSource.gmail.rawValue
        let existing = (try? ctx.fetch(FetchDescriptor<Signal>(
            predicate: #Predicate { $0.sourceRaw == gmailRaw }
        )))?.compactMap { $0.externalId } ?? []
        let seen = Set(existing)

        for fix in fixtures {
            if seen.contains(fix.externalId) { continue }
            let arrived = Date().addingTimeInterval(-Double.random(in: 60...3600))
            let signal = Signal(
                source: .gmail,
                externalId: fix.externalId,
                rawData: fix,
                summary: fix.subject,
                arrivedAt: arrived
            )
            ctx.insert(signal)
            ctx.insert(AppEvent(type: .signalReceived,
                                payload: SignalReceivedPayload(signalID: signal.id)))
        }
        try? ctx.save()
    }

    struct Message: Codable {
        let externalId: String
        let from: String
        let subject: String
        let snippet: String
    }

    private static let fixtures: [Message] = [
        .init(externalId: "gmail:karan-followup-may22",
              from: "karan@sequoiacap.com",
              subject: "Re: deck v3 — let's land this Tuesday",
              snippet: "Saw your v3 — the retention slide reads. Let's land Tuesday."),
        .init(externalId: "gmail:vfs-permit-update-may21",
              from: "no-reply@vfsglobal.com",
              subject: "Your Ireland study permit application — status update",
              snippet: "We've received your application. New slots open daily after 14:00 IST."),
        .init(externalId: "gmail:dublin-housing-may19",
              from: "alerts@daft.ie",
              subject: "3 new listings in Trinity area — under €2200",
              snippet: "3 listings matched your saved search.")
    ]
}

enum CalendarConnector {
    static func pollOnce(ctx: ModelContext) {
        let calRaw = SignalSource.calendar.rawValue
        let existing = (try? ctx.fetch(FetchDescriptor<Signal>(
            predicate: #Predicate { $0.sourceRaw == calRaw }
        )))?.compactMap { $0.externalId } ?? []
        let seen = Set(existing)
        let now = Date()
        for fix in fixtures {
            if seen.contains(fix.externalId) { continue }
            let arrival = fix.startOffsetSeconds.map { now.addingTimeInterval($0) } ?? now
            let signal = Signal(
                source: .calendar,
                externalId: fix.externalId,
                rawData: fix,
                summary: fix.title,
                arrivedAt: arrival
            )
            ctx.insert(signal)
            ctx.insert(AppEvent(type: .signalReceived,
                                payload: SignalReceivedPayload(signalID: signal.id)))
        }
        try? ctx.save()
    }

    struct Event: Codable {
        let externalId: String
        let title: String
        let location: String?
        let startOffsetSeconds: TimeInterval?
        let durationMinutes: Int?
    }

    private static let fixtures: [Event] = [
        .init(externalId: "cal:karan-may21",
              title: "Karan — second touch",
              location: "Bombay Gymkhana, lounge",
              startOffsetSeconds: 60 * 60 * 6,
              durationMinutes: 30),
        .init(externalId: "cal:sitting-may22",
              title: "Sitting for V.",
              location: "Bandra studio, above the bakery",
              startOffsetSeconds: 60 * 60 * 24,
              durationMinutes: 90),
        .init(externalId: "cal:trip-may23",
              title: "BOM → PGH",
              location: "T2",
              startOffsetSeconds: 60 * 60 * 50,
              durationMinutes: 200)
    ]
}

enum DriveConnector {
    static func pollOnce(ctx: ModelContext) {
        let driveRaw = SignalSource.drive.rawValue
        let existing = (try? ctx.fetch(FetchDescriptor<Signal>(
            predicate: #Predicate { $0.sourceRaw == driveRaw }
        )))?.compactMap { $0.externalId } ?? []
        let seen = Set(existing)
        for fix in fixtures {
            if seen.contains(fix.externalId) { continue }
            let signal = Signal(
                source: .drive,
                externalId: fix.externalId,
                rawData: fix,
                summary: fix.name,
                arrivedAt: Date().addingTimeInterval(-Double.random(in: 60...7200))
            )
            ctx.insert(signal)
            ctx.insert(AppEvent(type: .signalReceived,
                                payload: SignalReceivedPayload(signalID: signal.id)))
        }
        try? ctx.save()
    }

    struct Doc: Codable {
        let externalId: String
        let name: String
        let kind: String   // "deck" / "doc" / "sheet"
        let lastEditedBy: String
    }

    private static let fixtures: [Doc] = [
        .init(externalId: "drive:deck-v3",
              name: "Stratyfix Deck v3.pdf",
              kind: "deck",
              lastEditedBy: "you"),
        .init(externalId: "drive:retention-cohorts",
              name: "Retention by cohort — May.csv",
              kind: "sheet",
              lastEditedBy: "you"),
        .init(externalId: "drive:ceo-continuity-onepager",
              name: "CEO continuity — one-pager.docx",
              kind: "doc",
              lastEditedBy: "you")
    ]
}
