import Foundation

// MARK: - Run result

/// The result of an agent run — the final text reply plus a trace of the tool
/// calls made, for logging into `Brief.agentTraceJSON`. Provider-neutral: every
/// `LLMClient` returns this regardless of which model produced it.
struct RunResult {
    let finalText: String
    let trace: [TraceStep]
}

struct TraceStep: Codable {
    let kind: String        // "tool_call" | "tool_result" | "text"
    let name: String?
    let input: String?
    let output: String?
}

// MARK: - Errors

/// Errors shared by every LLM backend, so callers don't need to know which
/// engine is active.
enum LLMError: Error, LocalizedError {
    case missingKey(provider: String)
    case http(Int, String)
    case toolNotFound(String)
    case maxIterationsReached
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p):    return "No \(p) API key set. Add one in Settings."
        case .http(let s, let b):   return "HTTP \(s): \(b.prefix(200))"
        case .toolNotFound(let n):  return "Agent called unknown tool: \(n)"
        case .maxIterationsReached: return "Agent loop reached its limit"
        case .decoding(let s):      return "Could not decode model response: \(s)"
        }
    }
}

// MARK: - The swappable engine

/// A model backend that can run Atlas's agent loop. The loop shape is identical
/// across providers — system prompt + a user turn + a tool registry, looping on
/// tool calls until the model returns prose. Only the wire format differs, and
/// each conformer hides that.
///
/// Per PHILOSOPHY.md the model is a *rented, swappable engine*. Switching it is a
/// one-line change to `AtlasLLM.client`, never an architectural one.
protocol LLMClient {
    /// Whether this backend has the credentials it needs to run.
    var isConfigured: Bool { get }

    /// Run one agent task. `userText` is the opening user turn; wiring the system
    /// prompt (`AtlasSystemPrompt.text`) and tools is the conformer's job.
    func run(userText: String, tools: ToolRegistry) async throws -> RunResult

    /// One-shot completion (no tools, single turn) — for grounded answers and
    /// short summaries (e.g. the Search answer card). Returns the model's prose.
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
}

extension LLMClient {
    /// Default for engines that don't implement a one-shot path.
    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        throw LLMError.decoding("one-shot complete() not supported by this engine")
    }
}

/// The single place a provider is chosen. Everything else calls `AtlasLLM.run`
/// and never names a vendor.
enum AtlasLLM {
    /// The active engine. Default: Claude. Assign another `LLMClient` here
    /// (e.g. `GeminiTextClient()`) to A/B a different backend — that is the
    /// entire cost of switching models.
    static var client: LLMClient = ClaudeClient()

    /// Circuit breaker. Tripped when the API reports the account can't be used
    /// at all (no credits / bad auth). While tripped, `isConfigured` reads false
    /// so handlers degrade to the dormant fallback instead of hammering the API
    /// once per queued event. Reset on relaunch (or via `resetBreaker()`).
    private(set) static var breakerReason: String?
    static var isBreakerTripped: Bool { breakerReason != nil }
    static func resetBreaker() { breakerReason = nil }

    /// True when the active engine is ready to run: key set, breaker closed, AND
    /// today's token budget not yet spent.
    static var isConfigured: Bool { client.isConfigured && !isBreakerTripped && !LLMBudget.isExhausted }

    static func run(userText: String, tools: ToolRegistry) async throws -> RunResult {
        do {
            return try await client.run(userText: userText, tools: tools)
        } catch let LLMError.http(status, body) where isAccountError(status, body) {
            breakerReason = "HTTP \(status)"   // e.g. 400 no-credit, 401/403 auth
            throw LLMError.http(status, body)
        }
    }

    static func complete(system: String, user: String, maxTokens: Int = 512) async throws -> String {
        do {
            return try await client.complete(system: system, user: user, maxTokens: maxTokens)
        } catch let LLMError.http(status, body) where isAccountError(status, body) {
            breakerReason = "HTTP \(status)"
            throw LLMError.http(status, body)
        }
    }

    /// Account-level failures that won't fix themselves on retry — distinct from
    /// transient 429/5xx. Trips the breaker; everything else passes through.
    private static func isAccountError(_ status: Int, _ body: String) -> Bool {
        if status == 401 || status == 403 { return true }
        if status == 400 {
            let b = body.lowercased()
            return b.contains("credit balance") || b.contains("billing")
                || b.contains("insufficient") || b.contains("quota")
        }
        return false
    }
}

/// A per-day token budget — a safety cap so the background agent loop can't run
/// away. Engines report tokens via `record(_:)`; once the day's cap is reached,
/// `AtlasLLM.isConfigured` reads false and handlers degrade to the dormant
/// fallback until local midnight. Cap is read from
/// `UserDefaults["AtlasDailyTokenCap"]` (default 300k) so it's tunable without a
/// rebuild — `defaults write com.atlas.app AtlasDailyTokenCap 500000`.
enum LLMBudget {
    static var dailyCap: Int {
        let v = UserDefaults.standard.integer(forKey: "AtlasDailyTokenCap")
        return v > 0 ? v : 300_000
    }

    private static var dayStamp = ""
    private(set) static var tokensToday = 0

    private static func rollover() {
        let s = stamp()
        if s != dayStamp { dayStamp = s; tokensToday = 0 }
    }
    private static func stamp() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// True once the day's cap is reached.
    static var isExhausted: Bool { rollover(); return tokensToday >= dailyCap }
    /// Tokens spent so far today (for a future Settings readout).
    static var spentToday: Int { rollover(); return tokensToday }
    /// Record tokens reported by an engine (input + cache + output).
    static func record(_ tokens: Int) { rollover(); tokensToday += max(0, tokens) }
}

// MARK: - Tools (provider-neutral)

/// A tool result — `payload` is sent back to the model as the tool's output. Use
/// `.ok(...)` for normal returns, `.error(...)` to surface a recoverable problem
/// (e.g. "no such chapter") the model can react to.
enum ToolResult {
    case ok([String: Any])
    case error(String)

    var payload: [String: Any] {
        switch self {
        case .ok(let dict): return dict
        case .error(let s): return ["error": s]
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// A protocol every tool implements. `name` matches the model's tool-call name.
/// `parameters` is the JSONSchema for the arguments — the same shape feeds both
/// Gemini (`parameters`) and Claude (`input_schema`).
protocol AgentTool {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get }
    func dispatch(args: [String: Any]) async throws -> ToolResult
}

/// Registry of the tools available in a given agent invocation. Built fresh per
/// event so each tool can capture its own ModelContext.
struct ToolRegistry {
    private var tools: [String: AgentTool] = [:]

    mutating func register(_ tool: AgentTool) {
        tools[tool.name] = tool
    }

    /// All registered tools — each conformer maps these into its provider's
    /// tool-declaration shape.
    var all: [AgentTool] { Array(tools.values) }

    /// Gemini-shaped declarations: `{ name, description, parameters }`.
    func functionDeclarations() -> [[String: Any]] {
        tools.values.map { t in
            ["name": t.name, "description": t.description, "parameters": t.parameters]
        }
    }

    func dispatch(name: String, args: [String: Any]) async throws -> ToolResult {
        guard let t = tools[name] else { throw LLMError.toolNotFound(name) }
        return try await t.dispatch(args: args)
    }
}

// MARK: - JSON helper

func jsonCompact(_ any: Any) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: any, options: []),
       let s = String(data: data, encoding: .utf8) {
        return s
    }
    return String(describing: any)
}
