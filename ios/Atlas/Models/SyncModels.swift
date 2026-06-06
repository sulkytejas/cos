import Foundation
import SwiftData

/// Phase-4 delta-sync bookkeeping models (SERVER_ARCHITECTURE.md §4.d / §4.e).
///
/// These three `@Model` tables are the durable spine of the multi-device sync:
///   - `SyncCursor`  — the per-table `(updatedAt, id)` resume cursor for
///     `sync.pull`. Persisting it means a relaunch resumes the delta stream
///     instead of re-pulling the whole table.
///   - `OutboxItem`  — a durable, ordered queue of write-through intents. A
///     mutation writes its local row optimistically AND enqueues an `OutboxItem`
///     so an offline / failed write-through survives a kill and flushes on
///     reconnect, idempotently (each item carries a `clientRef` the server
///     dedupes on).
///   - `SyncMigration` — the one-way `local→server` bootstrap latch. Once the
///     `.server` cut-over has uploaded local-only rows and rewritten their ids,
///     this row is marked done so the client PERMANENTLY stops local generation
///     for synced types and never re-runs the bootstrap (§4.d).
///
/// All three live in the SAME store as the mirror (`atlas`), because they
/// describe the mirror's relationship to the server. The developer-only `.local`
/// fallback uses a SEPARATE store and never reaches this machinery.

/// Per-table delta cursor for `sync.pull`. One row per synced table name.
/// The cursor is `(updatedAt, id)` — for `chapter_links` the `id` component is
/// the synthetic `from|to|relation` sync key (server-side `linkSyncKey`).
@Model
final class SyncCursor {
    /// The synced table name, e.g. "chapters", "todos", "chapter_links".
    @Attribute(.unique) var table: String
    /// ISO-8601-UTC `updatedAt` of the last row consumed.
    var cursorUpdatedAt: String
    /// `id` (or link sync key) of the last row consumed at that `updatedAt`.
    var cursorId: String

    init(table: String, cursorUpdatedAt: String, cursorId: String) {
        self.table = table
        self.cursorUpdatedAt = cursorUpdatedAt
        self.cursorId = cursorId
    }
}

/// A durable write-through intent. Mutations enqueue one of these AFTER writing
/// the optimistic local row, so a flush-on-reconnect can replay the server
/// write-through idempotently (the server dedupes creates by `clientRef` and
/// guards transitions like approve/dismiss so an at-least-once replay can't
/// double-file — §4.d).
@Model
final class OutboxItem {
    /// Stable idempotency key. For a create this is the optimistic row's local
    /// id (so the server's `(userId, clientRef)` unique resolves the replay to
    /// one row); for a transition (approve/dismiss/brief-act/calendar-push) it is
    /// a fresh UUID — the server-side transition guard / `(source, externalId)`
    /// upsert provides the idempotency there.
    @Attribute(.unique) var clientRef: UUID
    /// The kind of intent — drives how `flushOutbox()` dispatches it.
    var kindRaw: String
    /// JSON-encoded payload specific to the kind (the API input or enough to
    /// reconstruct it). Decoded by `flushOutbox()`.
    var payloadJSON: Data
    /// FIFO ordering — items flush oldest-first so a create lands before the
    /// transition that depends on it.
    var createdAt: Date
    /// Replay attempts so far. A poison item (validation/4xx) is dropped after a
    /// ceiling rather than blocking the queue forever.
    var attempts: Int
    /// Last replay error, for Settings diagnostics.
    var lastError: String?

    init(clientRef: UUID = UUID(), kind: OutboxKind, payloadJSON: Data) {
        self.clientRef = clientRef
        self.kindRaw = kind.rawValue
        self.payloadJSON = payloadJSON
        self.createdAt = Date()
        self.attempts = 0
        self.lastError = nil
    }

    var kind: OutboxKind {
        get { OutboxKind(rawValue: kindRaw) ?? .approve }
        set { kindRaw = newValue.rawValue }
    }
}

/// The intents the outbox can carry. Each maps to one `AtlasAPI` write-through.
enum OutboxKind: String, Codable, CaseIterable {
    case approve          // proposal.approve  (transition-guarded server-side)
    case dismiss          // proposal.dismiss  (transition-guarded server-side)
    case briefAct         // brief.act         (status flip + brief_acted_on)
    case calendarSignal   // signal.ingest     (upsert on (source, externalId))
    case memoStrike       // turn.strike       (patch a memo line's struck flag)
    case memoKeep         // turn.keep         (seal the morning memo as kept)
}

/// The one-way `local→server` bootstrap latch (§4.d). A single row records that
/// the device has run the cut-over: uploaded its local-only rows, received
/// server ids, rewritten its local ids, and PERMANENTLY stopped local generation
/// for synced types. Idempotent: the bootstrap checks/sets this so it never runs
/// twice and the stop is durable across launches.
@Model
final class SyncMigration {
    /// Singleton key (always "primary").
    @Attribute(.unique) var key: String
    /// Whether the `local→server` bootstrap upload has completed.
    var bootstrapped: Bool
    /// When the cut-over completed (nil until done).
    var bootstrappedAt: Date?

    init(key: String = "primary", bootstrapped: Bool = false, bootstrappedAt: Date? = nil) {
        self.key = key
        self.bootstrapped = bootstrapped
        self.bootstrappedAt = bootstrappedAt
    }
}
