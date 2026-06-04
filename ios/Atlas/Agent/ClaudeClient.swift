import Foundation

/// ClaudeClient — NEUTRALIZED (SERVER_ARCHITECTURE.md §4.b / §4.e).
///
/// The brain moved to the server behind the one throttled AI gateway. There is
/// exactly one `new Anthropic()` and one `ANTHROPIC_API_KEY` read, and they live
/// on the server — never in the app. The former direct-to-Anthropic path that
/// lived here (the `https://api.anthropic.com/v1/messages` POST and the
/// `UserDefaults["AnthropicAPIKey"]` read) has been DELETED: shipping a build
/// that talks to Anthropic from the device, or that reads the key from
/// `UserDefaults`, is a distribution blocker.
///
/// This type is retained only as a no-op `LLMClient` so the legacy v0.3 surface
/// (not the shipping Ayumi UI) still compiles. It reports unconfigured and every
/// call throws — the on-device brain is gone. All inference now flows through
/// `AtlasRepo` → `AtlasAPI` → the server gateway.
struct ClaudeClient: LLMClient {
    var isConfigured: Bool { false }

    func run(userText: String, tools: ToolRegistry) async throws -> RunResult {
        throw LLMError.missingKey(provider: "server")
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        throw LLMError.missingKey(provider: "server")
    }
}
