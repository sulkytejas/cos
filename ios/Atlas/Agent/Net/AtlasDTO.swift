import Foundation

/// Hand-written Codable DTOs per endpoint (SERVER_ARCHITECTURE.md §4.a / §4.e).
///
/// These mirror the EXACT JSON the existing tRPC procedures return (the drizzle
/// row shapes in `src/db/schema.ts`) and accept. Hand-written so the enum raw
/// values (`journal_entry`, `chapter_link`, brief statuses, signal sources, etc.)
/// stay under our control and BYTE-COMPATIBLE with the server — a renamed case on
/// either side would silently break upsert/round-trip, so they are pinned here.
///
/// Server timestamps are ISO-8601-UTC strings (the §4.d normalization). We keep
/// them as `String` in the DTO and parse with `AtlasISO` at the repo boundary so
/// a non-standard fractional-second variant never crashes a decode.

// MARK: - Inputs (client → server)

/// `brief.act` action — pinned to the server's `z.enum(["start","snooze","dismiss","archive"])`.
enum BriefAction: String, Codable { case start, snooze, dismiss, archive }

struct BriefActInput: Encodable {
    let id: String
    let action: String   // BriefAction.rawValue
}

struct EventEmitInput: Encodable {
    let type: String     // EventType.rawValue (e.g. "capture_received")
    let payload: AnyEncodableValue
}

/// `ai.ask` input — field caps are enforced server-side (§4.a); the client sends
/// already-trimmed text.
struct AskInput: Encodable {
    let query: String
    var scope: String? = nil
    var context: String? = nil
    var history: [AskTurn] = []

    struct AskTurn: Encodable {
        let role: String   // "user" | "atlas"
        let text: String
    }
}

struct ProposalForReviewInput: Encodable {
    let type: String     // ProposalType.rawValue
}

/// `proposal.approve` — transition-guarded server-side; safe to retry.
struct ApproveInput: Encodable {
    let id: String
    var chosenValue: String? = nil
    var editedPayload: AnyEncodableValue? = nil
}

/// `turn.strike` — patch one morning-memo line's `struck` flag (Today agentic
/// flow v1). Striking a `proposal`-ref line server-side also dismisses the
/// still-pending proposal it stands for. Idempotent.
struct TurnStrikeInput: Encodable {
    let turnId: String
    let lineId: String
    let struck: Bool
    /// Word-level redline spans (nil = whole-line gesture / legacy behavior).
    var struckWords: [Int]? = nil
}

/// `turn.keep` — seal the morning memo as `kept` (status flip; idempotent if the
/// memo is already kept).
struct TurnKeepInput: Encodable {
    let turnId: String
}

/// `signal.ingest` — the EventKit calendar push (§4.e). Upserts on
/// `(source, externalId)`.
struct SignalIngestInput: Encodable {
    let source: String       // SignalSource.rawValue, e.g. "calendar"
    let externalId: String
    let rawData: AnyEncodableValue
    var summary: String? = nil
    var arrivedAt: String? = nil   // ISO-8601 UTC
}

/// `connector.authUrl` / `connector.status` / `connector.disconnect` source —
/// pinned to the server's `z.enum(["gmail","calendar","drive"])` (§4.f Phase 5).
enum ConnectorSource: String, Codable, CaseIterable {
    case gmail, calendar, drive
}

struct ConnectorSourceInput: Encodable {
    let source: String   // ConnectorSource.rawValue
}

// MARK: - Capture co-completion inputs (v0.7 — module MC)

/// `capture.complete` — the streaming-ghost + classifier step. The server
/// enqueues a `capture_complete` one_shot job (only the worker calls Anthropic),
/// polls it server-side, and returns the structured completion. `scope` is the
/// screen the well was summoned over (a grounding hint).
struct CaptureCompleteInput: Encodable {
    let fragment: String
    var scope: String? = nil
}

/// `capture.file` — commit the completed fragment as a note/todo/decision under a
/// chapter. Server-side `kind`/`source` default to `note`/`text`; we always send
/// them explicitly so the wire matches the prototype's forming tag.
struct CaptureFileInput: Encodable {
    let text: String
    let kind: String          // CoCaptureKind.rawValue: "todo" | "decision" | "note"
    var chapterId: String? = nil
    var answer: String? = nil
    let source: String        // "text" | "voice"
}

// MARK: - Trip / Living Chapter inputs (v0.7 — module MD)

/// `trip.get` — fetch the Trip-shaped chapter (seed + the caller's persisted
/// overlay + learned preferences applied on top).
struct TripGetInput: Encodable {
    let id: String
}

/// `trip.correct` — reconcile a correction ("no, I took the bus"). `targetId` is
/// the leg/stop id; `answer` is the chosen chip or the user's free text.
struct TripCorrectInput: Encodable {
    var tripId: String = "north"
    let targetId: String
    let answer: String
}

/// `trip.grantConnector` — consent for a source (HDFC / IRCTC / Calendar): flips
/// available→feeding and rewrites what Ayumi can now do.
struct TripGrantConnectorInput: Encodable {
    var tripId: String = "north"
    let id: String
}

// MARK: - Outputs (server → client)

struct OkDTO: Decodable {
    let ok: Bool
    var alreadyDecided: Bool? = nil
}

/// `connector.authUrl` → the Google consent URL to open in a browser /
/// ASWebAuthenticationSession. After consent the server's callback stores the
/// encrypted grant and the worker starts polling (§4.f Phase 5).
struct ConnectorAuthURLDTO: Decodable { let url: String }

/// `connector.status` (nullable) / one row of `connector.list`. Never carries any
/// token material — only the public connection state.
struct ConnectorStatusDTO: Decodable {
    let source: String
    var accountEmail: String? = nil
    let status: String          // "active" | "revoked"
    var lastPolledAt: String? = nil
    var lastError: String? = nil
}

struct ConnectorDisconnectDTO: Decodable { let disconnected: Bool }

struct EmitDTO: Decodable { let id: String }
struct AskJobDTO: Decodable { let jobId: String }

// MARK: - Capture co-completion outputs (v0.7 — module MC)

/// `capture.complete` → the well's co-completion. `ghost` is the suggested
/// remainder the well renders italic; `kind`/`chapterId` form the tag;
/// `question` is set ONLY when confidence is low (the one-question card);
/// `confidence` is advisory. The forming-tag *suffix* ("Stratyfix · due Tue") is
/// derived client-side from kind/chapterId — the server returns the structure,
/// not the display string.
struct CaptureCompleteDTO: Decodable {
    let ghost: String
    let kind: String            // "todo" | "decision" | "note"
    var chapterId: String? = nil
    var question: CaptureQuestionDTO? = nil
    let confidence: Double

    struct CaptureQuestionDTO: Decodable {
        let text: String
        let answers: [String]
    }
}

/// `capture.file` → the minted id, so the client reconciles its optimistic "Kept."
struct CaptureFileDTO: Decodable {
    let ok: Bool
    let id: String
}

// MARK: - Trip / Living Chapter outputs (v0.7 — module MD)

/// `trip.get` → the Trip-shaped chapter, mirroring the server's Zod `Trip`. This
/// is the LEAN reasoning model (legs/spend/connectors that corrections + grants
/// mutate); the repo merges it onto the richer offline seed (icons, sparklines,
/// build-steps, corrections) the design needs.
struct TripDTO: Decodable {
    let id: String
    let title: String
    let framing: String
    let dateRange: String
    let meta: String
    let stops: [StopDTO]
    let legs: [LegDTO]
    let spend: SpendDTO
    let recommendations: [RecommendationDTO]
    let tracking: [TrackingStatDTO]
    let connectors: [ConnectorDTO]
    let receipts: [ReceiptDTO]

    struct StopDTO: Decodable {
        let id: String
        let place: String
        let dates: String
        let note: String
        let mini: String
        let state: String           // "done" | "here" | "upcoming"
        let provenance: [String]    // ("booked" | "inferred" | "live")[]
        let collapsed: Bool
    }

    struct LegDTO: Decodable {
        let id: String
        let fromStop: String
        let toStop: String
        let mode: String
        let why: String
        let fare: String
        let booked: Bool
        let correctedByUser: Bool
    }

    struct SpendDTO: Decodable {
        let total: Int
        let projected: Int
        let currency: String
        let segments: [SegmentDTO]
        let sources: [String]

        struct SegmentDTO: Decodable {
            let key: String          // "flights" | "stays" | "food" | "travel"
            let label: String
            let amount: Int
        }
    }

    struct RecommendationDTO: Decodable {
        let id: String
        let title: String
        let blurb: String
        let signal: String
    }

    struct TrackingStatDTO: Decodable {
        let id: String
        let label: String
        let value: String
        let detail: String
        let source: String
    }

    struct ConnectorDTO: Decodable {
        let id: String
        let name: String
        let role: String
        let status: String          // "feeding" | "available"
        let unlockCopy: String
    }

    struct ReceiptDTO: Decodable {
        let id: String
        let label: String
        let sources: [String]
    }
}

/// `trip.correct` → the reconciled patch + the ripple {changed} + "what I learned".
/// The leg rewrite, the recomputed spend, and the durable preference all happen
/// server-side; the client applies `patch` and shows the ripple.
struct TripCorrectDTO: Decodable {
    let patch: PatchDTO
    let ripple: RippleDTO
    let learned: String

    struct PatchDTO: Decodable {
        let leg: LegPatchDTO
        var spend: SpendPatchDTO? = nil

        struct LegPatchDTO: Decodable {
            let id: String
            var mode: String? = nil
            var fare: String? = nil
            var booked: Bool? = nil
            var correctedByUser: Bool? = nil
        }
        struct SpendPatchDTO: Decodable {
            let total: Int
            let segments: [TripDTO.SpendDTO.SegmentDTO]
        }
    }
    struct RippleDTO: Decodable { let changed: String }
}

/// `trip.grantConnector` → the granted source's new state + copy, and whether the
/// chapter should re-derive on the next read.
struct TripGrantConnectorDTO: Decodable {
    let status: String          // "feeding"
    let role: String
    let unlockCopy: String
    let needsRederive: Bool
}

/// `event.status` — drives the submit→poll→read loop. On `done`, `result`
/// carries the job output: capture → `resultProposalIds`; ai_ask → `answer`.
struct EventStatusDTO: Decodable {
    let status: String       // pending | processing | done | failed
    var error: String? = nil
    var processedAt: String? = nil
    var result: JobResultDTO? = nil

    var isTerminal: Bool { status == "done" || status == "failed" }
}

struct JobResultDTO: Decodable {
    var answer: String? = nil
    var resultProposalIds: [String]? = nil
}

/// `signal.ingest` return — `isNew` tells us whether the worker was enqueued.
struct SignalIngestDTO: Decodable {
    let id: String
    let isNew: Bool
}

/// `signal.overnight` — "handled while you slept" headline counts.
struct OvernightDTO: Decodable {
    let total: Int
    let buckets: [String: Int]
}

/// `proposal.countsForToday` — nav badges + "handled while you slept" stat.
struct ProposalCountsDTO: Decodable {
    let pending: Int
    let filedToday: Int
    let filedByType: [String: Int]
}

/// `brief.forToday` row (a projection, not the full brief — no `structure`).
struct BriefSummaryDTO: Decodable {
    let id: String
    var chapterId: String? = nil
    let title: String
    let situationDescription: String
    var chapterTitle: String? = nil
    var relevance: String? = nil
    var when: String? = nil
    var drafted: String? = nil
    var preview: String? = nil
    let status: String        // BriefStatus.rawValue
    let surfaceAt: String
    let createdAt: String
}

/// `brief.byId` — the FULL brief row, incl. the `structure` JSON the renderer
/// consumes. `structure` is decoded lazily by the repo into `BriefStructure`.
struct BriefDTO: Decodable {
    let id: String
    var chapterId: String? = nil
    let title: String
    let situationDescription: String
    /// Raw `{ sections: [...] }` JSON — kept as a value so the repo can re-encode
    /// it into `Brief.structureData` (the BriefStructure render contract) without
    /// a lossy round-trip through typed fields.
    let structure: JSONValue
    var primaryAction: String? = nil
    var secondaryActions: [String]? = nil
    let status: String
    let surfaceAt: String
    var expiresAt: String? = nil
    var chapterTitle: String? = nil
    var relevance: String? = nil
    var when: String? = nil
    var drafted: String? = nil
    var preview: String? = nil
    let createdAt: String
    var updatedAt: String? = nil

    /// Re-encode the `structure` value back to JSON bytes for `Brief.structureData`.
    func structureData() -> Data {
        (try? JSONEncoder().encode(structure)) ?? Data("{\"sections\":[]}".utf8)
    }
}

/// `watcher.active` row.
struct WatcherDTO: Decodable {
    let id: String
    var chapterId: String? = nil
    let description: String
    let prompt: String
    let sourceType: String     // WatcherSourceType.rawValue (incl. "internal")
    var lastChecked: String? = nil
    let nextCheck: String
    let cadenceMinutes: Int
    let status: String         // WatcherStatus.rawValue
    var cadenceLabel: String? = nil
    let createdAt: String
}

/// A proposal row as `proposal.forReview` / `countsForToday` return it. The
/// payload/options are kept as raw JSON values (their shape depends on `type`).
struct ProposalDTO: Decodable {
    let id: String
    let type: String           // ProposalType.rawValue (e.g. "journal_entry")
    let proposedPayload: JSONValue
    var sourceBriefId: String? = nil
    var sourceSignalIds: [String]? = nil
    var chapterId: String? = nil
    let status: String         // ProposalStatus.rawValue
    let confidence: Double
    var reasoning: String? = nil
    var summary: String? = nil
    var sourceLabel: String? = nil
    var sourceMeta: String? = nil
    var question: String? = nil
    var setup: String? = nil
    var options: JSONValue? = nil
    let createdAt: String
    var decidedAt: String? = nil

    func proposedPayloadData() -> Data {
        (try? JSONEncoder().encode(proposedPayload)) ?? Data("{}".utf8)
    }
    /// Decode `options` into the model's `[ProposalOption]`, if present.
    func decodedOptions() -> [ProposalOption]? {
        guard let options else { return nil }
        guard let data = try? JSONEncoder().encode(options) else { return nil }
        return try? JSONDecoder().decode([ProposalOption].self, from: data)
    }
}

struct ProposalReviewDTO: Decodable {
    let pending: [ProposalDTO]
    let filedToday: [ProposalDTO]
}

/// `chapter.list` row (chapter + rolled-up todo progress).
struct ChapterListItemDTO: Decodable {
    let id: String
    let title: String
    let type: String           // ChapterType.rawValue
    let status: String         // ChapterStatus.rawValue
    var startDate: String? = nil
    var endDate: String? = nil
    var purpose: String? = nil
    let createdAt: String
    let updatedAt: String
    var todoCount: Int = 0
    var todoDone: Int = 0
    var progress: Double = 0
}

/// `chapter.get` — full chapter with children. Used by the detail screen.
struct ChapterDetailDTO: Decodable {
    let id: String
    let title: String
    let type: String
    let status: String
    var startDate: String? = nil
    var endDate: String? = nil
    var purpose: String? = nil
    let createdAt: String
    let updatedAt: String
    var todos: [TodoDTO] = []
    var decisions: [DecisionDTO] = []
    var entries: [EntryDTO] = []
    var links: [ChapterLinkDTO] = []
}

struct TodoDTO: Decodable {
    let id: String
    var chapterId: String? = nil
    let text: String
    let done: Bool
    var dueDate: String? = nil
    let source: String         // TodoSource.rawValue
    let createdAt: String
    var doneAt: String? = nil
}

struct DecisionDTO: Decodable {
    let id: String
    var chapterId: String? = nil
    let title: String
    var rationale: String? = nil
    var optionsConsidered: String? = nil
    let decidedAt: String
    let createdAt: String
}

struct EntryDTO: Decodable {
    let id: String
    var chapterId: String? = nil
    let date: String
    let content: String
    let source: String         // EntrySource.rawValue
    let createdAt: String
}

struct ChapterLinkDTO: Decodable {
    var fromId: String
    var toId: String
    let relation: String       // LinkRelation.rawValue
    var note: String? = nil
    var direction: String? = nil   // "outgoing" | "incoming" (from chapter.get)
    var other: ChapterListItemDTO? = nil
}

// MARK: - Type erasure + raw JSON

/// Encodes an arbitrary Encodable value, used to box heterogeneous payloads
/// (capture payloads, ingest rawData, edited proposal payloads) before they go
/// into a tRPC envelope.
struct AnyEncodableValue: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ value: some Encodable) { encodeFn = value.encode(to:) }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

/// A fully-general JSON value, so DTO fields whose shape varies (`structure`,
/// `proposedPayload`, `options`) survive a lossless decode→re-encode round-trip.
enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// MARK: - Timestamp parsing

/// Parses the server's ISO-8601-UTC timestamps (§4.d normalization) — tolerant
/// of both `…THH:MM:SS.sssZ` and `…THH:MM:SSZ`.
enum AtlasISO {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let noFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return withFraction.date(from: s) ?? noFraction.date(from: s)
    }

    static func string(_ d: Date) -> String { withFraction.string(from: d) }
}
