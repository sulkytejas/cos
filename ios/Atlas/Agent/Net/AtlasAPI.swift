import Foundation
import os

/// AtlasAPI — the ONLY network layer (SERVER_ARCHITECTURE.md §4.a / §4.e).
///
/// The thin client speaks tRPC-over-HTTP directly to the EXISTING procedures —
/// no parallel REST facade. The only wire friction is superjson's `{json, meta}`
/// envelope, solved here once:
///   - Queries  → `GET  /api/trpc/<proc>?input=<superjson-encoded>`
///   - Mutations→ `POST /api/trpc/<proc>` with body `{ "json": <payload> }`
///   - Every response is unwrapped from `result.data.json`.
///
/// Every request carries `Authorization: Bearer <deviceToken>` from the Keychain.
/// On `429` the gateway-forwarded `Retry-After` is honored with backoff (the
/// gateway owns the real throttle; this client just waits it out).
///
/// SECURITY (§4.e, gating): the base URL MUST be `https://`. A non-https base is
/// rejected at construction AND per request — otherwise the bearer token and all
/// personal data could travel cleartext.
///
/// An `actor` so the in-flight request state and the (rare) base-URL swap are
/// serialized without a lock.
actor AtlasAPI {
    static let shared = AtlasAPI()

    private let log = Logger(subsystem: "com.atlas.app", category: "AtlasAPI")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// The validated https base URL, e.g. `https://atlas.example.com`. nil until
    /// the user configures a server in Settings (reads serve the cache meanwhile).
    private var baseURL: URL?

    /// Default key under which the server URL is stored (advisory; Keychain holds
    /// the secret token, this is just the public endpoint).
    static let baseURLDefaultsKey = "AtlasServerURL"

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)

        decoder = JSONDecoder()
        encoder = JSONEncoder()

        if let saved = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey),
           let url = Self.validatedHTTPS(saved) {
            baseURL = url
        }
    }

    // MARK: - Configuration

    /// Set the server base URL. REJECTS any non-`https://` URL (§4.e). Returns
    /// false (and leaves the prior config untouched) if the string is not a valid
    /// https URL. Persists the public URL to UserDefaults on success.
    @discardableResult
    func setBaseURL(_ string: String) -> Bool {
        guard let url = Self.validatedHTTPS(string) else {
            log.error("rejected non-https base URL")
            return false
        }
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.baseURLDefaultsKey)
        return true
    }

    var configuredBaseURL: String? { baseURL?.absoluteString }
    var isConfigured: Bool { baseURL != nil && Keychain.hasDeviceToken }

    /// Validate + normalize a base URL: must parse, must be `https`, must have a
    /// host. Trailing slash trimmed so path joining is unambiguous.
    nonisolated static func validatedHTTPS(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "https",
              let host = comps.host, !host.isEmpty
        else { return nil }
        var s = trimmed
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    // MARK: - Public endpoint surface (DTOs in AtlasDTO.swift)

    // Today
    func briefForToday() async throws -> [BriefSummaryDTO] {
        try await query("brief.forToday")
    }
    func signalOvernight() async throws -> OvernightDTO {
        try await query("signal.overnight")
    }
    func watcherActive() async throws -> [WatcherDTO] {
        try await query("watcher.active")
    }
    func proposalCountsForToday() async throws -> ProposalCountsDTO {
        try await query("proposal.countsForToday")
    }

    // Brief
    func briefById(_ id: String) async throws -> BriefDTO? {
        try await query("brief.byId", input: id)
    }
    /// Wire Start/Snooze/Dismiss/Archive. Server flips status AND emits
    /// `brief_acted_on` in one round-trip.
    func briefAct(id: String, action: BriefAction) async throws -> OkDTO {
        try await mutate("brief.act", BriefActInput(id: id, action: action.rawValue))
    }

    // Capture / Ask job contract (submit → poll → read)
    /// Emit any event (capture, etc.); returns the job id to poll.
    func eventEmit(type: String, payload: some Encodable) async throws -> EmitDTO {
        try await mutate("event.emit", EventEmitInput(type: type, payload: AnyEncodableValue(payload)))
    }
    /// Poll a job. `nil` once the row is gone / never existed for this user.
    func eventStatus(_ id: String) async throws -> EventStatusDTO? {
        try await query("event.status", input: id)
    }
    /// Enqueue a grounded one-shot Ask; returns `{ jobId }` to poll via eventStatus.
    func aiAsk(_ input: AskInput) async throws -> AskJobDTO {
        try await mutate("ai.ask", input)
    }

    // Review
    func proposalForReview(type: String? = nil) async throws -> ProposalReviewDTO {
        if let type {
            return try await query("proposal.forReview", input: ProposalForReviewInput(type: type))
        }
        return try await query("proposal.forReview")
    }
    func proposalApprove(_ input: ApproveInput) async throws -> OkDTO {
        try await mutate("proposal.approve", input)
    }
    func proposalDismiss(_ id: String) async throws -> OkDTO {
        try await mutate("proposal.dismiss", id)
    }

    // Chapters
    func chapterList() async throws -> [ChapterListItemDTO] {
        try await query("chapter.list")
    }
    func chapterGet(_ id: String) async throws -> ChapterDetailDTO? {
        try await query("chapter.get", input: id)
    }
    func briefRecentByChapter() async throws -> [String] {
        try await query("brief.recentByChapter")
    }

    // Signals (EventKit push source, §4.e)
    /// Upserts on `(source, externalId)` — a per-foreground re-push won't dup.
    func signalIngest(_ input: SignalIngestInput) async throws -> SignalIngestDTO {
        try await mutate("signal.ingest", input)
    }

    // Connectors (real Gmail/Calendar/Drive OAuth, §4.f Phase 5). EventKit stays
    // the device-only calendar push fast-path; these drive the server-side grants.
    /// Get a Google consent URL to open in a browser/ASWebAuthenticationSession.
    func connectorAuthURL(source: ConnectorSource) async throws -> ConnectorAuthURLDTO {
        try await mutate("connector.authUrl", ConnectorSourceInput(source: source.rawValue))
    }
    /// All of the user's connector connections (for the Settings list).
    func connectorList() async throws -> [ConnectorStatusDTO] {
        try await query("connector.list")
    }
    /// One source's connection state, or nil if not connected.
    func connectorStatus(source: ConnectorSource) async throws -> ConnectorStatusDTO? {
        try await query("connector.status", input: ConnectorSourceInput(source: source.rawValue))
    }
    /// Disconnect a connector (soft-deletes the grant; the poller stops).
    func connectorDisconnect(source: ConnectorSource) async throws -> ConnectorDisconnectDTO {
        try await mutate("connector.disconnect", ConnectorSourceInput(source: source.rawValue))
    }

    // Capture co-completion (v0.7 — module MC). `complete` enqueues a
    // `capture_complete` one_shot job the WORKER drains through the single gateway
    // (the app NEVER calls Anthropic) and polls it server-side, returning the
    // structured ghost. `file` commits the completed fragment.
    func captureComplete(_ input: CaptureCompleteInput) async throws -> CaptureCompleteDTO {
        try await mutate("capture.complete", input)
    }
    func captureFile(_ input: CaptureFileInput) async throws -> CaptureFileDTO {
        try await mutate("capture.file", input)
    }

    // Trip / the Living Chapter (v0.7 — module MD). `get` renders the seed + the
    // caller's persisted overlay; `correct` reconciles a correction (real mutation
    // + recompute + learned preference); `grantConnector` flips a source to feeding.
    func tripGet(_ id: String) async throws -> TripDTO? {
        try await query("trip.get", input: TripGetInput(id: id))
    }
    func tripCorrect(_ input: TripCorrectInput) async throws -> TripCorrectDTO {
        try await mutate("trip.correct", input)
    }
    func tripGrantConnector(_ input: TripGrantConnectorInput) async throws -> TripGrantConnectorDTO {
        try await mutate("trip.grantConnector", input)
    }

    // Delta-sync (§4.d) — the bulk-read + one-way cut-over endpoints.
    /// Pull the next page of deltas (upserts + tombstones) per table since the
    /// client's cursors. The repo loops this until `hasMore` is false.
    func syncPull(_ input: SyncPullInput) async throws -> SyncPullDTO {
        try await query("sync.pull", input: input)
    }
    /// One-way `local→server` bootstrap: upload local-only rows, get back the
    /// `localId → serverId` mapping so the client rewrites its ids. Idempotent
    /// server-side (upsert by `(userId, clientRef)`), so a re-run is safe.
    func syncBootstrap(_ input: BootstrapInput) async throws -> BootstrapDTO {
        try await mutate("sync.bootstrap", input)
    }

    // MARK: - tRPC transport

    /// A query: `GET /api/trpc/<proc>` with the superjson-encoded `input` in the
    /// query string. `input` may be omitted for no-arg procedures.
    private func query<R: Decodable>(_ proc: String, input: (some Encodable)? = nil) async throws -> R {
        var path = "/api/trpc/\(proc)"
        if let input {
            // tRPC's fetch handler expects the transformer-serialized input; for
            // superjson that is `{ "json": <value> }`. Primitives need no meta.
            let envelope = SJEnvelope(json: AnyEncodableValue(input))
            let data = try encoder.encode(envelope)
            let encoded = String(decoding: data, as: UTF8.self)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            path += "?input=\(encoded)"
        }
        return try await send(method: "GET", path: path, body: nil)
    }

    /// Overload for the genuinely no-arg query (no `input` param at all).
    private func query<R: Decodable>(_ proc: String) async throws -> R {
        try await send(method: "GET", path: "/api/trpc/\(proc)", body: nil)
    }

    /// A mutation: `POST /api/trpc/<proc>` with body `{ "json": <payload> }`.
    private func mutate<R: Decodable>(_ proc: String, _ payload: some Encodable) async throws -> R {
        let envelope = SJEnvelope(json: AnyEncodableValue(payload))
        let body = try encoder.encode(envelope)
        return try await send(method: "POST", path: "/api/trpc/\(proc)", body: body)
    }

    /// Issue the request, unwrap `result.data.json`, with Retry-After backoff.
    private func send<R: Decodable>(method: String, path: String, body: Data?) async throws -> R {
        guard let base = baseURL else { throw AtlasAPIError.notConfigured }
        // Re-assert https per request (defense in depth — §4.e).
        guard base.scheme?.lowercased() == "https" else { throw AtlasAPIError.insecureBaseURL }
        guard let token = Keychain.deviceToken, !token.isEmpty else {
            throw AtlasAPIError.missingToken
        }
        guard let url = URL(string: base.absoluteString + path) else {
            throw AtlasAPIError.badURL
        }

        let maxAttempts = 4
        var attempt = 0
        while true {
            attempt += 1
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = body

            let data: Data
            let resp: URLResponse
            do {
                (data, resp) = try await session.data(for: req)
            } catch {
                // Transport failure (offline, DNS, TLS). Retry a couple times,
                // then bubble up so the caller can fall back to the cache.
                if attempt < maxAttempts {
                    try await backoff(attempt: attempt, retryAfter: nil)
                    continue
                }
                throw AtlasAPIError.transport(error)
            }
            guard let http = resp as? HTTPURLResponse else {
                throw AtlasAPIError.noHTTPResponse
            }

            switch http.statusCode {
            case 200..<300:
                return try unwrap(data)

            case 401, 403:
                throw AtlasAPIError.unauthorized

            case 429:
                // The gateway forwards its 429 with Retry-After (§4.a). Honor it.
                let ra = Self.retryAfterSeconds(http)
                log.info("429 throttled; retry-after=\(ra ?? -1, privacy: .public)s attempt=\(attempt)")
                if attempt < maxAttempts {
                    try await backoff(attempt: attempt, retryAfter: ra)
                    continue
                }
                throw AtlasAPIError.rateLimited(retryAfter: ra)

            case 500..<600:
                if attempt < maxAttempts {
                    try await backoff(attempt: attempt, retryAfter: Self.retryAfterSeconds(http))
                    continue
                }
                throw AtlasAPIError.server(http.statusCode, Self.errorMessage(data))

            default:
                throw AtlasAPIError.server(http.statusCode, Self.errorMessage(data))
            }
        }
    }

    /// Unwrap the superjson tRPC success envelope `{ result: { data: { json } } }`.
    private func unwrap<R: Decodable>(_ data: Data) throws -> R {
        do {
            let env = try decoder.decode(TRPCSuccess<R>.self, from: data)
            return env.result.data.json
        } catch {
            throw AtlasAPIError.decoding(error)
        }
    }

    // MARK: - Backoff

    /// Sleep before the next attempt. Prefers a server-supplied Retry-After;
    /// otherwise full-jitter exponential backoff (1s, 2s, 4s …, capped 30s).
    private func backoff(attempt: Int, retryAfter: TimeInterval?) async throws {
        let seconds: TimeInterval
        if let retryAfter, retryAfter > 0 {
            seconds = min(retryAfter, 60)
        } else {
            let cap = min(pow(2.0, Double(attempt - 1)), 30)
            seconds = Double.random(in: 0...cap)
        }
        try await Task.sleep(nanoseconds: UInt64(max(0.05, seconds) * 1_000_000_000))
    }

    /// Parse `Retry-After` (delta-seconds or an HTTP-date) into seconds-from-now.
    nonisolated static func retryAfterSeconds(_ http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = (http.value(forHTTPHeaderField: "Retry-After")
            ?? http.value(forHTTPHeaderField: "retry-after"))?
            .trimmingCharacters(in: .whitespaces) else { return nil }
        if let secs = TimeInterval(raw) { return max(0, secs) }
        // HTTP-date form.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = fmt.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    /// Pull a human-readable message out of a tRPC error envelope, if present.
    nonisolated static func errorMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any] {
            if let msg = err["message"] as? String { return msg }
            if let json = err["json"] as? [String: Any], let msg = json["message"] as? String {
                return msg
            }
        }
        return String(decoding: data.prefix(500), as: UTF8.self)
    }
}

// MARK: - Errors

enum AtlasAPIError: LocalizedError {
    case notConfigured
    case insecureBaseURL
    case missingToken
    case badURL
    case noHTTPResponse
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int, String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:      return "No server URL configured."
        case .insecureBaseURL:    return "Server URL must use https."
        case .missingToken:       return "No device token. Pair this device in Settings."
        case .badURL:             return "Malformed request URL."
        case .noHTTPResponse:     return "No HTTP response."
        case .unauthorized:       return "Device token rejected (401/403)."
        case .rateLimited(let r): return "Rate limited.\(r.map { " Retry in \(Int($0))s." } ?? "")"
        case .server(let c, let m): return "Server error \(c): \(m)"
        case .transport(let e):   return "Network error: \(e.localizedDescription)"
        case .decoding(let e):    return "Decode error: \(e.localizedDescription)"
        }
    }

    /// Reads that should fall back to the cache silently (offline / not yet set up)
    /// rather than surfacing an error banner.
    var isOfflineLike: Bool {
        switch self {
        case .notConfigured, .missingToken, .transport: return true
        default: return false
        }
    }
}

// MARK: - superjson envelopes

/// The superjson input wrapper: `{ "json": <value> }`. Primitive/object values
/// need no `meta`, so we omit it (matches what tRPC's deserializer accepts).
private struct SJEnvelope: Encodable {
    let json: AnyEncodableValue
}

/// tRPC success envelope under superjson: `{ result: { data: { json: <R> } } }`.
private struct TRPCSuccess<R: Decodable>: Decodable {
    struct Result: Decodable { let data: DataBox }
    struct DataBox: Decodable { let json: R }
    let result: Result
}

extension CharacterSet {
    /// URL-query value-safe set (drops `&`, `=`, `+`, `?` etc. so the encoded
    /// JSON survives intact in `?input=`).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}
