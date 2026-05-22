import Foundation
import os

/// Thin client for Google's Gemini Generative Language API. We use
/// `gemini-2.5-flash-image` (a.k.a. "Nano Banana") for one-shot image
/// generation from a text prompt. The key is read from UserDefaults under
/// `GeminiAPIKey` — set it from Settings → AI.
enum GeminiClient {
    static let modelID = "gemini-2.5-flash-image"
    static let log = Logger(subsystem: "com.atlas.app", category: "GeminiClient")

    enum ClientError: Error, LocalizedError {
        case missingKey
        case badResponse(Int, String)
        case rateLimited(retryAfter: TimeInterval)
        case billingRequired
        case billingBlocked(projectID: String)
        case noImageInResponse
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "No Gemini API key set. Add one in Settings → AI."
            case .badResponse(let status, let body):
                return "Gemini returned HTTP \(status): \(body)"
            case .rateLimited(let s):
                return "Rate limited — retry in \(Int(s))s."
            case .billingRequired:
                return "Image generation requires billing on your Google Cloud project. Free-tier quota is 0 — enable billing at console.cloud.google.com/billing then try again."
            case .billingBlocked(let project):
                return "Google flagged billing on project \(project). Open console.cloud.google.com/billing — look for an \"Action required\" banner. Common causes: payment method declined, account under fraud review (usually clears in a few hours), or country/region needs extra verification."
            case .noImageInResponse:
                return "Gemini response had no inline image data."
            case .decoding(let s):
                return "Could not decode Gemini response: \(s)"
            }
        }
    }

    static var apiKey: String? {
        let k = UserDefaults.standard.string(forKey: "GeminiAPIKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }

    /// Sends a text prompt and returns image bytes. Automatically retries up
    /// to 3 times on HTTP 429, honoring Gemini's `retryDelay` field when
    /// present.
    static func generateImage(prompt: String) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await rawGenerate(prompt: prompt)
            } catch let ClientError.rateLimited(retryAfter) {
                guard attempt < 3 else {
                    throw ClientError.rateLimited(retryAfter: retryAfter)
                }
                // Exponential backoff floor: 8s, 18s, 32s — plus whatever
                // Gemini's retryDelay suggests.
                let backoff = max(retryAfter, Double(attempt) * Double(attempt) * 8)
                log.info("⏳ 429 retry in \(backoff, format: .fixed(precision: 1))s (attempt \(attempt))")
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
    }

    private static func rawGenerate(prompt: String) async throws -> Data {
        guard let key = apiKey else { throw ClientError.missingKey }

        let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent"
        )!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        // Request shape matches the canonical @google/genai SDK output exactly:
        //   contents: [{ role: "user", parts: [{ text }] }]
        //   generationConfig: { responseModalities: ["IMAGE", "TEXT"] }
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]],
            "generationConfig": [
                "responseModalities": ["IMAGE", "TEXT"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("POST \(modelID, privacy: .public) (prompt=\(prompt.count) chars)")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            log.error("no http response")
            throw ClientError.badResponse(-1, "no http response")
        }
        log.info("← HTTP \(http.statusCode) (\(data.count) bytes)")

        // 429 → distinguish "no quota at all" (billing required) from
        //         genuine per-minute throttling.
        if http.statusCode == 429 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if bodyText.contains("limit: 0") || bodyText.range(of: #"limit"\s*:\s*0[\s,}]"#, options: .regularExpression) != nil {
                log.error("billing required: free-tier limit is 0 for image gen")
                throw ClientError.billingRequired
            }
            let delay = parseRetryDelay(in: bodyText) ?? 12
            log.error("rate limited; retryDelay=\(delay)s body=\(bodyText, privacy: .public)")
            throw ClientError.rateLimited(retryAfter: delay)
        }

        // 403 → Google's billing-decision system blocked the project
        if http.statusCode == 403 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if bodyText.contains("dunning") || bodyText.contains("Lightning") ||
               bodyText.contains("billing") || bodyText.contains("BILLING") {
                let project = extractProjectID(from: bodyText) ?? "(unknown)"
                log.error("billing blocked for project \(project, privacy: .public)")
                throw ClientError.billingBlocked(projectID: project)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            log.error("bad status: \(bodyText, privacy: .public)")
            throw ClientError.badResponse(http.statusCode, bodyText)
        }

        // Walk candidates[].content.parts[] for an inlineData with mime image/*
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.decoding("root not object")
        }
        if let promptFeedback = root["promptFeedback"] as? [String: Any] {
            log.info("promptFeedback: \(String(describing: promptFeedback), privacy: .public)")
        }
        guard let candidates = root["candidates"] as? [[String: Any]] else {
            log.error("no candidates: \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
            throw ClientError.decoding("no candidates array")
        }
        for cand in candidates {
            if let finish = cand["finishReason"] as? String {
                log.info("candidate finishReason=\(finish, privacy: .public)")
            }
            guard let content = cand["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let inline = part["inlineData"] as? [String: Any] ?? part["inline_data"] as? [String: Any],
                   let mime = inline["mimeType"] as? String ?? inline["mime_type"] as? String,
                   mime.hasPrefix("image/"),
                   let b64 = inline["data"] as? String,
                   let bytes = Data(base64Encoded: b64) {
                    log.info("✓ got image bytes \(bytes.count) mime=\(mime, privacy: .public)")
                    return bytes
                }
                if let text = part["text"] as? String {
                    log.info("part text='\(text.prefix(120), privacy: .public)'")
                }
            }
        }
        log.error("no inlineData in any candidate; raw=\(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
        throw ClientError.noImageInResponse
    }

    /// Pull "projects/874970147402" out of an error body.
    private static func extractProjectID(from body: String) -> String? {
        guard let range = body.range(of: #"projects/(\d+)"#, options: .regularExpression) else {
            return nil
        }
        return String(body[range])
    }

    /// Pull `"retryDelay": "12s"` out of the 429 error JSON, if present.
    private static func parseRetryDelay(in body: String) -> TimeInterval? {
        // The structure is nested under error.details[].retryDelay = "12s"
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let details = error["details"] as? [[String: Any]] else { return nil }
        for d in details {
            if let s = d["retryDelay"] as? String {
                // Format is like "12s" or "1m30s"
                if s.hasSuffix("s"), let n = Double(s.dropLast()) { return n }
            }
        }
        return nil
    }
}
