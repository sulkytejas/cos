import Foundation

/// GeminiAgent / GeminiTextClient — NEUTRALIZED (SERVER_ARCHITECTURE.md §4.e).
///
/// This was an on-device LLM agent loop (a swappable `AtlasLLM.client` backend)
/// that POSTed to Gemini's `generateContent` with the device's
/// `UserDefaults["GeminiAPIKey"]`. In the thin-client cut-over the brain runs on
/// the server behind one throttled gateway, so no provider inference happens on
/// the device. The HTTP loop and the key read have been DELETED.
///
/// `GeminiTextClient` is retained only as a no-op `LLMClient` so any legacy
/// reference still type-checks; it reports unconfigured and every call throws.
struct GeminiTextClient: LLMClient {
    var isConfigured: Bool { false }

    func run(userText: String, tools: ToolRegistry) async throws -> RunResult {
        throw LLMError.missingKey(provider: "server")
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        throw LLMError.missingKey(provider: "server")
    }
}
