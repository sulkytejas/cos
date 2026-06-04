import Foundation
import SwiftData

/// AgentTools — NEUTRALIZED (SERVER_ARCHITECTURE.md §4.e).
///
/// The agent's read/write tool registry (chapter_query, person_lookup,
/// create_brief, create_proposal, create_watcher, web_search, …) ran inside the
/// on-device agent loop. The brain now runs on the SERVER worker, where the tool
/// loop lives inside the throttled gateway (`runAgentLoop`, §4.b/§4.c). No tools
/// execute on the device anymore.
///
/// Retained only so the legacy `LLMClient` surface still type-checks:
/// `registry(for:scopeChapter:)` returns an EMPTY registry, and `AnyCodable`
/// (a small heterogeneous-JSON Codable shim) stays since it's a generic helper.
enum AgentTools {
    /// Empty registry — there are no on-device tools. The neutralized
    /// `LLMClient`s throw before they would ever dispatch one.
    static func registry(for ctx: ModelContext, scopeChapter: Chapter? = nil) -> ToolRegistry {
        ToolRegistry()
    }
}

// MARK: - Heterogeneous JSON shim (generic helper, kept)

/// A `Codable` box over an arbitrary JSON value — used to (de)serialize untyped
/// payload dictionaries. Provider-neutral; not tied to any agent path.
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
