import Foundation
import os

/// ClaudeClient — Atlas's default engine. A thin client over Anthropic's
/// Messages API (`/v1/messages`) with tool use. Per PHILOSOPHY.md the model is a
/// rented, swappable engine: this conformer hides Anthropic's wire format behind
/// the provider-neutral `LLMClient`.
///
/// One agent loop iteration:
///   1. POST `system` + `messages` + `tools`.
///   2. If the reply contains `tool_use` blocks, dispatch each via the
///      ToolRegistry and send `tool_result` blocks back as the next user turn.
///   3. If it returns prose with no tool calls, collect the text and finish.
///
/// Caps mirror the Gemini path: 8 iterations, 180s wall clock, 3 retries on
/// transient HTTP (429 / 5xx). The key lives in UserDefaults["AnthropicAPIKey"]
/// — set it in Settings → engine.
struct ClaudeClient: LLMClient {
    /// Default model. Override via UserDefaults["AnthropicModel"] without a rebuild.
    static let defaultModel = "claude-sonnet-4-6"
    static let apiVersion = "2023-06-01"
    static let log = Logger(subsystem: "com.atlas.app", category: "ClaudeClient")

    var isConfigured: Bool { Self.apiKey() != nil }

    func run(userText: String, tools: ToolRegistry) async throws -> RunResult {
        guard let key = Self.apiKey() else { throw LLMError.missingKey(provider: "Anthropic") }

        let configured = UserDefaults.standard.string(forKey: "AnthropicModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (configured?.isEmpty == false) ? configured! : Self.defaultModel

        // Anthropic tool declarations: { name, description, input_schema }.
        // Sorted by name so the tools block is byte-identical across events →
        // prompt-cache hits. cache_control on the LAST tool caches the whole
        // system+tools prefix (the big, immutable part) so it isn't re-counted
        // as fresh input tokens every call (the org input-token/min rate lever).
        var toolDecls: [[String: Any]] = tools.all
            .map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] as [String: Any] }
            .sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        if !toolDecls.isEmpty {
            toolDecls[toolDecls.count - 1]["cache_control"] = ["type": "ephemeral"]
        }

        // The conversation, as Anthropic content-block messages.
        var messages: [[String: Any]] = [[
            "role": "user",
            "content": [["type": "text", "text": userText]]
        ]]
        var trace: [TraceStep] = []

        let start = Date()
        let wallClockBudgetSec: TimeInterval = 180

        for iter in 0..<8 {
            if Date().timeIntervalSince(start) > wallClockBudgetSec {
                Self.log.error("agent loop timed out at iter \(iter)")
                throw LLMError.maxIterationsReached
            }

            var body: [String: Any] = [
                "model": model,
                "max_tokens": 2048,
                // System as a cached content block (prompt caching, GA): the
                // immutable system prompt is read from cache after the first call
                // instead of re-billed/re-counted as fresh input each iteration.
                "system": [["type": "text", "text": AtlasSystemPrompt.text,
                            "cache_control": ["type": "ephemeral"]]],
                "messages": messages,
                "temperature": 0.4
            ]
            if !toolDecls.isEmpty { body["tools"] = toolDecls }

            let (assistantContent, finalText, calls) = try await Self.sendOnce(body: body, key: key, model: model)

            // Echo the assistant turn back verbatim so tool_use ids line up.
            messages.append(["role": "assistant", "content": assistantContent])

            if calls.isEmpty {
                if let t = finalText, !t.isEmpty {
                    trace.append(.init(kind: "text", name: nil, input: nil, output: t))
                }
                return RunResult(finalText: finalText ?? "", trace: trace)
            }

            // Dispatch each tool call; collect tool_result blocks for the next turn.
            var resultBlocks: [[String: Any]] = []
            for call in calls {
                trace.append(.init(kind: "tool_call", name: call.name,
                                   input: jsonCompact(call.input), output: nil))
                let result: ToolResult
                do {
                    result = try await tools.dispatch(name: call.name, args: call.input)
                } catch {
                    result = .error(String(describing: error))
                }
                trace.append(.init(kind: "tool_result", name: call.name,
                                   input: nil, output: jsonCompact(result.payload)))
                var block: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": call.id,
                    "content": jsonCompact(result.payload)
                ]
                if result.isError { block["is_error"] = true }
                resultBlocks.append(block)
            }
            messages.append(["role": "user", "content": resultBlocks])
        }
        throw LLMError.maxIterationsReached
    }

    // MARK: - HTTP

    private struct ToolCall { let id: String; let name: String; let input: [String: Any] }

    private static func sendOnce(
        body: [String: Any], key: String, model: String
    ) async throws -> (assistantContent: [[String: Any]], finalText: String?, calls: [ToolCall]) {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let payload = try JSONSerialization.data(withJSONObject: body)

        // 3-attempt retry on transient errors (429, 5xx). Backoff 1s → 3s → 7s.
        var attempt = 0
        var data = Data()
        var httpStatus = -1
        while attempt < 3 {
            attempt += 1
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
            req.httpBody = payload

            log.info("POST \(model, privacy: .public) (\(payload.count) bytes) attempt=\(attempt)")
            let (resp, urlResp) = try await URLSession.shared.data(for: req)
            data = resp
            guard let http = urlResp as? HTTPURLResponse else {
                throw LLMError.http(-1, "no http response")
            }
            httpStatus = http.statusCode
            log.info("← HTTP \(http.statusCode) (\(data.count) bytes)")

            if (200..<300).contains(http.statusCode) { break }
            let isTransient = http.statusCode == 429 || (500..<600).contains(http.statusCode)
            if !isTransient || attempt >= 3 {
                throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            let backoff: TimeInterval = [1, 3, 7][attempt - 1]
            log.info("retrying after \(backoff)s")
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
        if !(200..<300).contains(httpStatus) {
            throw LLMError.http(httpStatus, String(data: data, encoding: .utf8) ?? "")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else {
            throw LLMError.decoding("missing content array")
        }

        var text: String? = nil
        var calls: [ToolCall] = []
        for block in content {
            let type = block["type"] as? String
            if type == "text" {
                if let t = block["text"] as? String { text = (text ?? "") + t }
            } else if type == "tool_use" {
                if let id = block["id"] as? String, let name = block["name"] as? String {
                    let input = (block["input"] as? [String: Any]) ?? [:]
                    calls.append(ToolCall(id: id, name: name, input: input))
                }
            }
        }
        return (assistantContent: content, finalText: text, calls: calls)
    }

    private static func apiKey() -> String? {
        let k = UserDefaults.standard.string(forKey: "AnthropicAPIKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }
}
