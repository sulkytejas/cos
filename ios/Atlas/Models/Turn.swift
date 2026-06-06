import Foundation
import SwiftData

/// A Turn — one entry in the Today conversational thread (Today agentic flow v1).
///
/// The Today screen is no longer a hardcoded script: it is a real thread of
/// `Turn` rows, mirrored from the server's `turns` table the same way `Brief`
/// mirrors `briefs`. Each turn is either Ayumi's (`ayumi`) or the user's
/// (`user`); the worker's nightly daily-scan composes a "morning turn" whose
/// `body` is a 1–2 sentence VERDICT (rendered on Today) and whose `memo` is the
/// full, redlineable letter (struck line-by-line in Review, then "kept").
///
/// Voice rule (documented for whoever reads this thread): every sentence's
/// subject is the user's world, never the agent's process. Each memo line is a
/// disposition — held / folded / prepared / watching — not a status report.
///
/// This `@Model` is the iOS mirror; it carries NO `user_id` (the device is a
/// single-user cache). The JSON blobs (`briefIds`/`memo`/`connector`/`meta`) are
/// stored as `Data?` and decoded lazily through the computed accessors below, so
/// the keys round-trip byte-compatibly with the server's `turns` row shape.
@Model
final class Turn {
    @Attribute(.unique) var id: UUID
    /// "ayumi" | "user" — see `TurnRole`.
    var roleRaw: String
    /// "morning" | "message" | "thinking" — see `TurnKind`.
    var kindRaw: String
    /// The turn body (Ayumi-markup: paragraphs on "\n\n"; *roman*; ==accent==).
    /// For a morning turn this is the VERDICT shown on Today.
    var body: String
    /// "6 sources · email, voice memo, calendar, deck v3" — the src-tag line.
    var sourceTag: String?

    /// JSON-encoded `[UUID]` of the briefs this turn references (capsule embeds).
    var briefIdsJSON: Data?
    /// JSON-encoded `TurnMemo` — the redlineable letter (nil for plain turns).
    var memoJSON: Data?
    /// JSON-encoded `TurnConnector` — at most one connector suggestion (nil mostly).
    var connectorJSON: Data?
    /// JSON-encoded `{ windowStart, windowEnd }` overnight window (morning turns).
    var metaJSON: Data?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        role: TurnRole,
        kind: TurnKind = .message,
        body: String,
        sourceTag: String? = nil,
        briefIds: [UUID]? = nil,
        memo: TurnMemo? = nil,
        connector: TurnConnector? = nil,
        window: (start: Date, end: Date)? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.kindRaw = kind.rawValue
        self.body = body
        self.sourceTag = sourceTag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        // Route the structured fields through the computed setters so the
        // encoding lives in one place (and stays in lockstep with the getters).
        if let briefIds { self.briefIds = briefIds }
        if let memo { self.memo = memo }
        if let connector { self.connector = connector }
        if let window { self.window = window }
    }

    // MARK: - Computed accessors (enum + JSON re-encode, byte-compatible keys)

    var role: TurnRole {
        get { TurnRole(rawValue: roleRaw) ?? .ayumi }
        set { roleRaw = newValue.rawValue }
    }
    var kind: TurnKind {
        get { TurnKind(rawValue: kindRaw) ?? .message }
        set { kindRaw = newValue.rawValue }
    }

    /// The briefs this turn references — decoded from `briefIdsJSON`. Setting
    /// re-encodes to `Data` (nil array clears the blob).
    var briefIds: [UUID] {
        get {
            guard let data = briefIdsJSON else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set { briefIdsJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }

    /// The redlineable letter — decoded from `memoJSON`. nil when the turn has no
    /// memo (a plain message / the user's reply / Ayumi's thinking line).
    var memo: TurnMemo? {
        get {
            guard let data = memoJSON else { return nil }
            return try? JSONDecoder().decode(TurnMemo.self, from: data)
        }
        set { memoJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The single connector suggestion this turn may carry (nil mostly).
    var connector: TurnConnector? {
        get {
            guard let data = connectorJSON else { return nil }
            return try? JSONDecoder().decode(TurnConnector.self, from: data)
        }
        set { connectorJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The overnight window `[start, end]` for the "while you slept" divider on
    /// the morning turn. nil when the turn carries no `meta`.
    var window: (start: Date, end: Date)? {
        get {
            guard let data = metaJSON,
                  let m = try? JSONDecoder().decode(TurnMeta.self, from: data),
                  let s = AtlasISO.date(m.windowStart),
                  let e = AtlasISO.date(m.windowEnd)
            else { return nil }
            return (s, e)
        }
        set {
            guard let nv = newValue else { metaJSON = nil; return }
            let m = TurnMeta(windowStart: AtlasISO.string(nv.start),
                             windowEnd: AtlasISO.string(nv.end))
            metaJSON = try? JSONEncoder().encode(m)
        }
    }
}

/// "ayumi" | "user" — byte-compatible with the server `turnRoles` enum.
enum TurnRole: String, Codable, CaseIterable {
    case ayumi, user
}

/// "morning" | "message" | "thinking" — byte-compatible with `turnKinds`.
enum TurnKind: String, Codable, CaseIterable {
    case morning, message, thinking
}

// MARK: - Memo / connector / meta Codables (server JSON keys EXACTLY)

/// The redlineable letter. `lines` are dispositions the user can strike; once
/// the user "keeps" it, `status` flips to `kept` (`keptBy` 'user', or 'auto' for
/// a stale draft the worker sealed at the next scan).
struct TurnMemo: Codable {
    var lines: [TurnMemoLine]
    /// "draft" | "kept".
    var status: String
    /// ISO-8601-UTC instant the memo was kept (nil while draft).
    var keptAt: String?
    /// "user" | "auto" (nil while draft).
    var keptBy: String?
}

/// One disposition line in the memo. `refKind`/`refId` link it to the output it
/// describes (a brief or a proposal), so striking a proposal-ref line can also
/// dismiss the still-pending proposal it stands for.
struct TurnMemoLine: Codable {
    let id: String
    var text: String
    /// "brief" | "proposal" | nil.
    var refKind: String?
    /// The referenced brief/proposal id (nil when `refKind` is nil).
    var refId: String?
    var struck: Bool
}

/// At most one connector suggestion the morning turn may carry — only when a
/// concrete observed gap exists. `source` is gmail | calendar | drive.
struct TurnConnector: Codable {
    let source: String
    let copy: String
}

/// The overnight window for the "while you slept" divider. Persisted ISO-8601.
struct TurnMeta: Codable {
    let windowStart: String
    let windowEnd: String
}

// MARK: - Ayumi markup parser (paragraphs → prose runs)

/// Parse an Ayumi-markup `body` into paragraphs of `ProseRun`s for `ayumiProse`.
///
/// Grammar (shared with the server / web renderer):
///   - paragraphs are separated by "\n\n";
///   - `*text*`  → a `.roman` run (de-italicized emphasis for names/numbers);
///   - `==text==` → an `.accent` run (the teal wash);
///   - everything else is `.italic` (the default serif voice).
///
/// Robustness: an UNTERMINATED marker (a lone `*` or `==` with no closer) is
/// treated as LITERAL text — the parser never drops characters, so a malformed
/// body still renders verbatim rather than vanishing. Empty paragraphs collapse
/// to a single empty italic run so the paragraph count is preserved.
func parseAyumiMarkup(_ s: String) -> [[ProseRun]] {
    // Split on the blank-line paragraph break. `omittingEmptySubsequences:
    // false` keeps intentional empty paragraphs (rare, but lossless).
    let paragraphs = s.components(separatedBy: "\n\n")
    return paragraphs.map { parseParagraph($0) }
}

/// Tokenize ONE paragraph into runs. Scans left-to-right; on a `*` or `==`
/// opener it looks for the matching closer and emits a styled run, otherwise the
/// marker degrades to literal text.
private func parseParagraph(_ para: String) -> [ProseRun] {
    var runs: [ProseRun] = []
    var literal = ""                 // accumulates the current italic span
    let chars = Array(para)
    var i = 0

    func flushLiteral() {
        if !literal.isEmpty { runs.append(ProseRun(literal, .italic)); literal = "" }
    }

    while i < chars.count {
        // `==accent==` — check the two-char marker first (so a `==` isn't read
        // as a stray `=` then `=`).
        if i + 1 < chars.count, chars[i] == "=", chars[i + 1] == "=" {
            if let close = findClose(chars, from: i + 2, marker: "==") {
                let inner = String(chars[(i + 2)..<close])
                flushLiteral()
                runs.append(ProseRun(inner, .accent))
                i = close + 2
                continue
            }
            // No closer — emit the `==` literally and keep scanning.
            literal.append("=="); i += 2; continue
        }
        // `*roman*`
        if chars[i] == "*" {
            if let close = findClose(chars, from: i + 1, marker: "*") {
                let inner = String(chars[(i + 1)..<close])
                flushLiteral()
                runs.append(ProseRun(inner, .roman))
                i = close + 1
                continue
            }
            literal.append("*"); i += 1; continue
        }
        literal.append(chars[i]); i += 1
    }
    flushLiteral()
    // An empty paragraph still needs one run so paragraph spacing is preserved.
    return runs.isEmpty ? [ProseRun("", .italic)] : runs
}

/// Find the index of the closing `marker` (`*` or `==`) at or after `from`, or
/// nil if the paragraph ends without one (→ the opener is literal).
private func findClose(_ chars: [Character], from: Int, marker: String) -> Int? {
    var j = from
    if marker == "==" {
        while j + 1 < chars.count {
            if chars[j] == "=", chars[j + 1] == "=" { return j }
            j += 1
        }
        return nil
    }
    // single-char `*`
    while j < chars.count {
        if chars[j] == "*" { return j }
        j += 1
    }
    return nil
}
