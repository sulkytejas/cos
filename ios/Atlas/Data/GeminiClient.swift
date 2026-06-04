import Foundation

/// GeminiClient — NEUTRALIZED (SERVER_ARCHITECTURE.md §4.e).
///
/// This was a direct device→Google image-generation path (chapter-icon art).
/// In the thin-client cut-over all model traffic flows through the server
/// gateway, so the device no longer holds provider keys or makes provider
/// calls. The former `https://generativelanguage.googleapis.com` POST and the
/// `UserDefaults["GeminiAPIKey"]` read have been DELETED.
///
/// Retained only so the legacy v0.3 `IconGenerator` (not the shipping Ayumi UI)
/// compiles: `apiKey` is always nil — `IconGenerator.generateMissing` guards on
/// it and cleanly no-ops — and `generateImage` throws.
enum GeminiClient {
    enum ClientError: Error, LocalizedError {
        case missingKey
        case disabled

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Image generation runs on the server now."
            case .disabled:   return "On-device image generation is disabled."
            }
        }
    }

    /// Always nil — no provider key lives on the device anymore.
    static var apiKey: String? { nil }

    static func generateImage(prompt: String) async throws -> Data {
        throw ClientError.disabled
    }
}
