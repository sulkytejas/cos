/**
 * Gateway configuration — the single place where models, per-route rate-limit
 * bucket sizes, concurrency, retry policy, and the per-user/day budget live.
 *
 * SERVER_ARCHITECTURE.md §4.b — "DEFAULT TO TIER 1, auto-raise from headers":
 * we ship conservative Tier-1-safe caps (85% of the Tier-1 published limits) and
 * the gateway clamps each bucket to min(configured, anthropic-ratelimit-*-limit)
 * read off every response. Over-throttling is recoverable; breaching is not.
 *
 * Callers route by INTENT (`agent` | `one_shot`), never by model string — the
 * gateway picks the model. Sonnet and Haiku are SEPARATE rate-limit pools, so
 * each route gets its own independent triple bucket.
 *
 * Every numeric is env-overridable so the operator can raise/lower without a
 * code change (e.g. once the real org tier is confirmed from the Console).
 */

/** The two intents a caller may request. The gateway maps these to models. */
export type Route = "agent" | "one_shot";

/** Models pinned in exactly one place (§1: "Models pinned in one place"). */
export const MODELS: Record<Route, string> = {
  agent: "claude-sonnet-4-6",
  one_shot: "claude-haiku-4-5",
};

/** Per-route bucket configuration. */
export interface RouteConfig {
  /** Intent name. */
  route: Route;
  /** Model id the gateway sends for this route. */
  model: string;
  /** Requests per minute. */
  rpm: number;
  /** Uncached input tokens per minute (input + cache_creation; cache_read is free). */
  itpm: number;
  /** Output tokens per minute. */
  otpm: number;
  /** Default max_tokens reserved per request against the OTPM bucket. */
  maxTokens: number;
}

/**
 * Read a positive integer from the environment, falling back to `def`.
 * A non-numeric or non-positive value falls back (never silently zeroes a bucket).
 */
function envInt(name: string, def: number): number {
  const raw = process.env[name];
  if (raw == null || raw.trim() === "") return def;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : def;
}

/**
 * Tier-1 published limits (the conservative default the design ships):
 *   Sonnet 4.x Tier 1 = 50 RPM / 30K ITPM / 8K OTPM
 *   Haiku 4.5  Tier 1 = 50 RPM / 50K ITPM / 10K OTPM
 * We start at 85% of those (the numbers in the §4.b table) and let the
 * header-clamp raise them if the org is actually a higher tier.
 */
export const ROUTES: Record<Route, RouteConfig> = {
  agent: {
    route: "agent",
    model: MODELS.agent,
    rpm: envInt("GATEWAY_AGENT_RPM", 42),
    itpm: envInt("GATEWAY_AGENT_ITPM", 25_500),
    otpm: envInt("GATEWAY_AGENT_OTPM", 6_800),
    maxTokens: envInt("GATEWAY_AGENT_MAX_TOKENS", 4_096),
  },
  one_shot: {
    route: "one_shot",
    model: MODELS.one_shot,
    rpm: envInt("GATEWAY_ONE_SHOT_RPM", 42),
    itpm: envInt("GATEWAY_ONE_SHOT_ITPM", 42_500),
    otpm: envInt("GATEWAY_ONE_SHOT_OTPM", 8_500),
    maxTokens: envInt("GATEWAY_ONE_SHOT_MAX_TOKENS", 1_024),
  },
};

/**
 * Global network concurrency cap shared across both pools (§4.b). One slot is
 * RESERVED for `one_shot`/interactive so an overnight `agent` burst can never
 * fully starve a live Ask: at most (maxConcurrency - reservedForOneShot)
 * `agent` calls may be in flight at once.
 */
export const CONCURRENCY = {
  maxConcurrency: envInt("GATEWAY_MAX_CONCURRENCY", 4),
  reservedForOneShot: envInt("GATEWAY_RESERVED_ONE_SHOT", 1),
} as const;

/**
 * Per-user/day token budget. Defined against input + cache_creation + output
 * ONLY — free cache reads are excluded (§4.b: "porting the iOS number but
 * fixing its accounting").
 */
export const PER_USER_DAILY_TOKEN_CAP = envInt("GATEWAY_DAILY_TOKEN_CAP", 300_000);

/** Full-jitter exponential backoff for transient (429/5xx/network) failures. */
export const RETRY = {
  retryMax: envInt("GATEWAY_RETRY_MAX", 5),
  retryBaseMs: envInt("GATEWAY_RETRY_BASE_MS", 1_000),
  retryCapMs: envInt("GATEWAY_RETRY_CAP_MS", 60_000),
} as const;

/** Agent tool-use loop ceiling (§4.b: every turn re-enters the buckets). */
export const MAX_TURNS = envInt("GATEWAY_MAX_TURNS", 12);

/**
 * Circuit breaker for non-self-healing failures (401/403/credit). When tripped,
 * acquires fail fast for this cooldown instead of hammering a dead key.
 */
export const CIRCUIT = {
  cooldownMs: envInt("GATEWAY_CIRCUIT_COOLDOWN_MS", 60_000),
} as const;

/**
 * Acceleration-limit (429 without token exhaustion) cooldown: how long to hold
 * a reduced admission rate before recovering, so a full resume doesn't
 * immediately re-trigger the limit.
 */
export const ACCEL_COOLDOWN_MS = envInt("GATEWAY_ACCEL_COOLDOWN_MS", 15_000);

/**
 * Char→token divisor for estimateInputTokens. ~3.5 chars per token; only the
 * NEW turn is estimated when the prefix is cached (the full prefix is reserved
 * once, on the cache-write turn). Tunable for safety margin.
 */
export const CHARS_PER_TOKEN = Number(process.env.GATEWAY_CHARS_PER_TOKEN ?? "3.5");
