import Foundation

/// Delta-sync DTOs (SERVER_ARCHITECTURE.md §4.d). These mirror the EXACT wire
/// shape of `sync.pull` / `sync.bootstrap` in `src/server/routers/sync.ts`.
///
/// `sync.pull` returns, per table, the next page of full rows (`rows`), the ids
/// of soft-deleted rows to drop (`tombstones`), the resume cursor (`nextCursor`),
/// and `hasMore`. The client loops `pull` until every table's `hasMore` is false
/// — that is how a 500-row single-tick burst drains across pages with no
/// skips/repeats (the `(updatedAt, id)` cursor is total and monotonic).
///
/// The full rows are drizzle `select()` output: camelCase keys, ISO-8601-UTC
/// timestamps (the §4.d normalization), enum raw values byte-compatible with the
/// `@Model` enums. Every synced row carries `updatedAt`; tombstones additionally
/// carry `deletedAt` (but the client keys deletes off the `tombstones` id list,
/// not the row body).

// MARK: - pull input / envelope

/// Per-table `(updatedAt, id)` cursor. `id` is the synthetic sync key for
/// `chapter_links`.
struct SyncCursorDTO: Codable {
    let updatedAt: String
    let id: String
}

/// `sync.pull` input: the per-table cursors the client last consumed (an OMITTED
/// table means "from the beginning" — the server reads `cursors[name] ?? null`),
/// the page limit, and an optional table subset.
struct SyncPullInput: Encodable {
    /// table name → resume cursor. Tables with no stored cursor are simply
    /// absent (equivalent to a null cursor server-side).
    var cursors: [String: SyncCursorDTO]
    var limit: Int = 500
    var tables: [String]? = nil
}

/// One table's slice of a pull. `rows` are full live rows to upsert; `tombstones`
/// are ids (or link sync keys) to delete from the mirror.
struct SyncTableSlice: Decodable {
    var rows: [SyncRow] = []
    var tombstones: [String] = []
    var nextCursor: SyncCursorDTO? = nil
    var hasMore: Bool = false
}

/// `sync.pull` output: a slice per table, an aggregate `hasMore`, and the
/// server's clock (for skew diagnostics only — conflict policy is
/// server-stamped-on-receipt, so the client never compares against it).
struct SyncPullDTO: Decodable {
    let tables: [String: SyncTableSlice]
    let hasMore: Bool
    let serverTime: String
}

// MARK: - generic row

/// A single synced row, decoded as a generic JSON object so ONE slice type can
/// carry every table's heterogeneous shape. The repo dispatches per table name
/// and reads typed fields off this via the accessors below — which keeps enum
/// raw values and timestamp parsing under our control (byte-compatible with the
/// server) without 8 parallel slice generics.
struct SyncRow: Decodable {
    let fields: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.fields = try c.decode([String: JSONValue].self)
    }

    // Typed accessors over the raw JSON value map.
    func string(_ key: String) -> String? {
        if case .string(let s)? = fields[key] { return s }
        return nil
    }
    func bool(_ key: String) -> Bool? {
        switch fields[key] {
        case .bool(let b)?:   return b
        case .number(let n)?: return n != 0     // drizzle boolean mode → 0/1
        default:              return nil
        }
    }
    func double(_ key: String) -> Double? {
        if case .number(let n)? = fields[key] { return n }
        if case .string(let s)? = fields[key] { return Double(s) }
        return nil
    }
    func int(_ key: String) -> Int? { double(key).map { Int($0) } }
    /// A nested JSON value (objects/arrays like `structure`, `proposedPayload`).
    func json(_ key: String) -> JSONValue? {
        guard let v = fields[key] else { return nil }
        if case .null = v { return nil }
        return v
    }
    /// Re-encode a nested JSON value back to bytes for a `@Model` blob field.
    func jsonData(_ key: String, fallback: String = "{}") -> Data {
        guard let v = json(key), let data = try? JSONEncoder().encode(v) else {
            return Data(fallback.utf8)
        }
        return data
    }

    /// The row id (canonical). Present on every ID-keyed table.
    var id: String? { string("id") }
    /// The row's `updatedAt` — the cursor's primary key component.
    var updatedAt: String? { string("updatedAt") }
}

// MARK: - bootstrap input (one-way local→server, §4.d)

/// `sync.bootstrap` input. Children carry `chapterRef` = the parent chapter's
/// LOCAL id (its `clientRef`), resolved server-side against the chapter mapping
/// produced in the same call. Timestamps are ISO-8601-UTC.
struct BootstrapInput: Encodable {
    var chapters: [BootstrapChapter] = []
    var todos: [BootstrapTodo] = []
    var decisions: [BootstrapDecision] = []
    var entries: [BootstrapEntry] = []

    struct BootstrapChapter: Encodable {
        let clientRef: String
        let title: String
        let type: String
        var status: String = "active"
        var startDate: String? = nil
        var endDate: String? = nil
        var purpose: String? = nil
        var createdAt: String? = nil
        var updatedAt: String? = nil
    }
    struct BootstrapTodo: Encodable {
        let clientRef: String
        let chapterRef: String
        let text: String
        var done: Bool = false
        var dueDate: String? = nil
        var source: String = "manual"
        var createdAt: String? = nil
        var updatedAt: String? = nil
    }
    struct BootstrapDecision: Encodable {
        let clientRef: String
        let chapterRef: String
        let title: String
        var rationale: String? = nil
        var optionsConsidered: String? = nil
        let decidedAt: String
        var source: String = "manual"
        var createdAt: String? = nil
        var updatedAt: String? = nil
    }
    struct BootstrapEntry: Encodable {
        let clientRef: String
        let chapterRef: String
        let date: String
        let content: String
        var source: String = "manual"
        var createdAt: String? = nil
        var updatedAt: String? = nil
    }
}

/// `sync.bootstrap` output: per-table `localId(clientRef) → serverId` maps the
/// client uses to rewrite its local ids and child FKs.
struct BootstrapDTO: Decodable {
    struct Mapping: Decodable {
        var chapters: [String: String] = [:]
        var todos: [String: String] = [:]
        var decisions: [String: String] = [:]
        var entries: [String: String] = [:]
    }
    let mapping: Mapping
    let serverTime: String
}

// MARK: - outbox replay payloads

/// The persisted body of an `OutboxItem`, one case per `OutboxKind`. Encoded into
/// `OutboxItem.payloadJSON` at enqueue and decoded by `flushOutbox()` to rebuild
/// the exact `AtlasAPI` write-through. The item's `clientRef` provides the
/// idempotency key, so a replay of an already-applied item is a server no-op.
enum OutboxPayload: Codable {
    case approve(id: String, chosenValue: String?)
    case dismiss(id: String)
    case briefAct(id: String, action: String)
    case calendarSignal(SignalIngestPayload)

    /// A self-contained, replayable copy of the calendar push (so the outbox can
    /// re-send it on reconnect without re-reading EventKit).
    struct SignalIngestPayload: Codable {
        let source: String
        let externalId: String
        let rawData: JSONValue
        var summary: String? = nil
        var arrivedAt: String? = nil
    }
}
