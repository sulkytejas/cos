import Foundation
import os

/// GeminiAgent — thin HTTP client around Gemini's `generateContent` endpoint
/// with function-calling. Reuses the same API key as GeminiClient (image gen)
/// from UserDefaults["GeminiAPIKey"].
///
/// One agent loop iteration:
///   1. POST to gemini-2.5-flash with tools + chat history.
///   2. Inspect the response for functionCall parts.
///   3. If any: dispatch each via the ToolRegistry, append the
///      functionResponse to the chat history, loop.
///   4. If none: collect the text reply, exit with success.
///
/// Hard caps: 8 iterations, 90s wall-clock, 4 retries on transient HTTP error.
enum GeminiAgent {
    static let modelID = "gemini-2.5-flash"
    static let log = Logger(subsystem: "com.atlas.app", category: "GeminiAgent")

    enum AgentError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case toolNotFound(String)
        case maxIterationsReached
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:           return "No Gemini API key set. Add one in Settings → AI."
            case .http(let s, let b):   return "Gemini HTTP \(s): \(b.prefix(200))"
            case .toolNotFound(let n):  return "Agent called unknown tool: \(n)"
            case .maxIterationsReached: return "Agent loop reached max iterations"
            case .decoding(let s):      return "Could not decode Gemini response: \(s)"
            }
        }
    }

    // RunResult and TraceStep are now provider-neutral types in LLMClient.swift,
    // shared by every engine. GeminiAgent.run still returns a RunResult.

    /// Run an agent loop. `userTurns` is the initial user message(s); the
    /// system prompt is prepended via systemInstruction (Gemini supports
    /// `systemInstruction` on generateContent).
    static func run(
        userText: String,
        tools: ToolRegistry
    ) async throws -> RunResult {
        guard let key = apiKey() else { throw AgentError.missingKey }

        // Initial history — just the user turn.
        var contents: [[String: Any]] = [[
            "role": "user",
            "parts": [["text": userText]]
        ]]
        var trace: [TraceStep] = []

        let tdecls = tools.functionDeclarations()
        let start = Date()
        // 180s wall clock — leaves room for web_fetches (12s each) chained with
        // 4-8 Gemini round trips. Earlier 90s cap was too tight for real-world
        // prompts that hit external resources.
        let wallClockBudgetSec: TimeInterval = 180

        for iter in 0..<8 {
            if Date().timeIntervalSince(start) > wallClockBudgetSec {
                log.error("agent loop timed out at iter \(iter)")
                throw AgentError.maxIterationsReached
            }

            let body: [String: Any] = [
                "systemInstruction": [
                    "parts": [["text": AtlasSystemPrompt.text]]
                ],
                "contents": contents,
                "tools": [["functionDeclarations": tdecls]],
                "toolConfig": [
                    "functionCallingConfig": ["mode": "AUTO"]
                ],
                "generationConfig": [
                    "temperature": 0.4,
                    "maxOutputTokens": 2048
                ]
            ]

            let (modelPart, finalText, calls) = try await sendOnce(body: body, key: key)
            // Append the model's turn with explicit role so Gemini's
            // alternating-turn validation passes on the next iteration.
            var modelTurn = modelPart
            modelTurn["role"] = "model"
            contents.append(modelTurn)

            if calls.isEmpty {
                if let t = finalText { trace.append(.init(kind: "text", name: nil, input: nil, output: t)) }
                return RunResult(finalText: finalText ?? "", trace: trace)
            }

            // Execute each call in order; collect functionResponse parts to send back.
            var responseParts: [[String: Any]] = []
            for call in calls {
                trace.append(.init(
                    kind: "tool_call",
                    name: call.name,
                    input: jsonCompact(call.args),
                    output: nil
                ))
                let result: ToolResult
                do {
                    result = try await tools.dispatch(name: call.name, args: call.args)
                } catch {
                    result = .error(String(describing: error))
                }
                trace.append(.init(
                    kind: "tool_result",
                    name: call.name,
                    input: nil,
                    output: jsonCompact(result.payload)
                ))
                responseParts.append([
                    "functionResponse": [
                        "name": call.name,
                        "response": result.payload
                    ]
                ])
            }
            contents.append([
                "role": "user",
                "parts": responseParts
            ])
        }
        throw AgentError.maxIterationsReached
    }

    // MARK: - HTTP

    private struct FuncCall { let name: String; let args: [String: Any] }

    private static func sendOnce(body: [String: Any], key: String) async throws -> (modelPart: [String: Any], finalText: String?, calls: [FuncCall]) {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent")!
        let payload = try JSONSerialization.data(withJSONObject: body)

        // 3-attempt retry for transient errors (429, 5xx). Exponential backoff
        // 1s → 3s → 7s. Other errors fail fast.
        var attempt = 0
        var data = Data()
        var httpStatus = -1
        while attempt < 3 {
            attempt += 1
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = payload

            log.info("POST \(modelID, privacy: .public) (\(payload.count) bytes) attempt=\(attempt)")
            let (resp, urlResp) = try await URLSession.shared.data(for: req)
            data = resp
            guard let http = urlResp as? HTTPURLResponse else {
                throw AgentError.http(-1, "no http response")
            }
            httpStatus = http.statusCode
            log.info("← HTTP \(http.statusCode) (\(data.count) bytes)")

            if (200..<300).contains(http.statusCode) { break }
            // Retry only on transient errors
            let isTransient = http.statusCode == 429 || (500..<600).contains(http.statusCode)
            if !isTransient || attempt >= 3 {
                throw AgentError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            let backoff: TimeInterval = [1, 3, 7][attempt - 1]
            log.info("retrying after \(backoff)s")
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
        if !(200..<300).contains(httpStatus) {
            throw AgentError.http(httpStatus, String(data: data, encoding: .utf8) ?? "")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cands = root["candidates"] as? [[String: Any]],
              let first = cands.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AgentError.decoding("missing candidates[0].content.parts")
        }

        var text: String? = nil
        var calls: [FuncCall] = []
        for p in parts {
            if let t = p["text"] as? String {
                text = (text ?? "") + t
            }
            if let fc = p["functionCall"] as? [String: Any] ?? p["function_call"] as? [String: Any],
               let n = fc["name"] as? String {
                let args = (fc["args"] as? [String: Any]) ?? [:]
                calls.append(FuncCall(name: n, args: args))
            }
        }
        return (modelPart: content, finalText: text, calls: calls)
    }

    private static func apiKey() -> String? {
        let k = UserDefaults.standard.string(forKey: "GeminiAPIKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }
}

// MARK: - LLMClient conformance

/// Gemini as a swappable Atlas engine. `ClaudeClient` is the default (see
/// `AtlasLLM.client`); assign `GeminiTextClient()` there to run on Gemini
/// instead. The loop above is unchanged — this only adapts it to `LLMClient`.
///
/// `ToolResult`, `AgentTool`, `ToolRegistry`, and `jsonCompact` now live in
/// LLMClient.swift so every engine shares them.
struct GeminiTextClient: LLMClient {
    var isConfigured: Bool {
        UserDefaults.standard.string(forKey: "GeminiAPIKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func run(userText: String, tools: ToolRegistry) async throws -> RunResult {
        try await GeminiAgent.run(userText: userText, tools: tools)
    }
}
