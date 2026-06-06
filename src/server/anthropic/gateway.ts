/**
 * THE AI GATEWAY — the one choke point every Anthropic call passes through.
 *
 * SERVER_ARCHITECTURE.md §4.b. This module is:
 *   - the ONLY `new Anthropic()` in the codebase
 *   - the ONLY reader of `ANTHROPIC_API_KEY`
 *   - the ONLY caller of `messages.create`
 * An ESLint `no-restricted-imports` rule bans `@anthropic-ai/sdk` everywhere
 * else so this invariant can't silently regress.
 *
 * Two public functions, both routing by INTENT (never by model string):
 *   - createMessage(req, ctx)   — a throttled 1:1 wrapper around messages.create
 *   - runAgentLoop(opts)        — the worker's tool-use loop moved INSIDE the
 *                                 gateway, so EVERY turn (up to MAX_TURNS=12)
 *                                 re-enters the buckets, not just the first call.
 * Plus prewarm() — a max_tokens:0 cache-write on the agent prefix at startup.
 *
 * Prompt caching (the highest-leverage lever): `system` is sent as a content
 * block with cache_control ephemeral ttl 1h, and the tool list is sorted by
 * name with cache_control on the last tool — a byte-stable prefix that caches
 * tools+system together. ttl 1h (not 5m) because overnight scans have gaps > 5
 * min, so a 5-min entry would expire between events and re-pay the write premium.
 */
import Anthropic, { APIError } from "@anthropic-ai/sdk";
import { randomUUID } from "node:crypto";
import {
  ACCEL_COOLDOWN_MS,
  CHARS_PER_TOKEN,
  CIRCUIT,
  MAX_TURNS,
  RETRY,
  ROUTES,
  type Route,
} from "./config";
import {
  BucketPool,
  CircuitOpenError,
  backoffDelayMs,
  sleep,
  type ChargeableUsage,
  type ReportedLimits,
  type Reservation,
} from "./buckets";
import { chargeUsageLedger, isOverDailyBudget } from "./ledger";

/** Thrown when a user has exhausted their per-day token budget. */
export class BudgetExceededError extends Error {
  constructor(public readonly userId: string) {
    super("daily token budget exceeded");
    this.name = "BudgetExceededError";
  }
}

/**
 * The agent loop produced no brief because of a failure that WON'T heal on a
 * retry — bad/unparseable final JSON, schema validation, or exceeding the turn
 * ceiling. The queue fails the event immediately (no MAX_ATTEMPTS re-runs) and
 * records `events.error`. See worker/src/queue.ts `isNonTransient`.
 */
export class NonTransientAgentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NonTransientAgentError";
  }
}

/**
 * The agent loop failed for a reason that MAY heal on a retry — a `send()` that
 * exhausted its internal retries (429/5xx/network). The queue routes this
 * through `handleFailure` so attempts/MAX_ATTEMPTS retry it, then fails after
 * the cap. See worker/src/queue.ts `isNonTransient`/`handleFailure`.
 */
export class TransientAgentError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message);
    this.name = "TransientAgentError";
    if (options?.cause !== undefined) (this as { cause?: unknown }).cause = options.cause;
  }
}

// ─────────────────────────── SDK client (the only one) ───────────────────────────

const apiKey = process.env.ANTHROPIC_API_KEY;
/** Single shared SDK client. Constructed even without a key so the stub path works. */
const client = new Anthropic({ apiKey: apiKey ?? "missing" });

/** One process-wide bucket pool — authoritative because only this process calls the API. */
const pool = new BucketPool(ROUTES);

// ─────────────────────────── cache-control typing ───────────────────────────
//
// Older @anthropic-ai/sdk type definitions only declare `{ type: "ephemeral" }`
// on cache_control and don't type the `ttl` field, even though the wire API
// accepts it (1h TTL is GA — no beta header). We define a structurally-precise
// local type and cast at the SDK boundary so the gateway compiles across SDK
// versions while still sending a valid `ttl: "1h"`.
type CacheControl = { type: "ephemeral"; ttl?: "5m" | "1h" };
const CACHE_1H: CacheControl = { type: "ephemeral", ttl: "1h" };

/** A tool definition the gateway accepts (the shape worker/src/tools emits). */
export interface ToolDef {
  name: string;
  description?: string;
  input_schema: Record<string, unknown>;
}

// ─────────────────────────── public request/result types ───────────────────────────

/** A throttled one-shot request. `route` selects the model + bucket pool. */
export interface GatewayRequest {
  route: Route;
  /** Plain system string OR pre-built content blocks. The gateway caches it. */
  system?: string;
  messages: Anthropic.MessageParam[];
  /** Optional tools; sorted by name + cache_control applied by the gateway. */
  tools?: ToolDef[];
  /** Override the route's default max_tokens (OTPM reservation). */
  maxTokens?: number;
}

/** Per-call context — carries the user for the per-user/day budget ledger. */
export interface GatewayContext {
  userId: string;
}

/** Re-exported so callers (worker persist.ts) share one AgentResult contract. */
export interface AgentTraceEntry {
  turn: number;
  kind: "model_text" | "tool_use" | "tool_result";
  payload: unknown;
}

export interface BriefOutput {
  title?: string;
  situation?: string;
  structure?: { sections: Array<{ kind: string; data: unknown }> };
  primary_action?: string;
  secondary_actions?: string[];
  chapter_id?: string | null;
  chapter_title?: string;
  relevance?: string;
  when?: string;
  preview?: string;
  proposals?: Array<{
    type: string;
    payload: Record<string, unknown>;
    chapter_id?: string | null;
    confidence: number;
    reasoning?: string;
    summary?: string;
    source_label?: string;
    source_meta?: string;
    setup?: string;
    question?: string;
    options?: Array<{ label: string; value: string; result?: string; type?: string }>;
  }>;
  watchers_to_create?: Array<{
    description: string;
    prompt: string;
    source_type?: string;
    cadence_minutes?: number;
    cadence_label?: string;
    chapter_id?: string | null;
  }>;
  /**
   * The morning turn (Today agentic flow v1). Emitted ONLY for daily scans —
   * the run context says so. `verdict` is the 1-2 sentence line shown on Today;
   * `lines` are the redlineable memo dispositions (each references a brief or a
   * proposal_index into `proposals` so persist can resolve a refId). `connector`
   * is at most one suggestion, only on a concrete observed gap.
   */
  day_memo?: {
    verdict: string;
    /** `note_ids` (memory Phase 5.1): notebook note ids a line leaned on — striking the line strikes them. */
    lines: Array<{ text: string; brief?: boolean; proposal_index?: number; note_ids?: string[] }>;
    source_tag?: string;
    connector?: { source: string; copy: string };
  };
  /**
   * Advisory chapter palette — the vocabulary of component kinds this chapter's
   * life will need. Emitted ONLY for chapter_created/chapter_updated runs.
   */
  palette?: string[];
  /**
   * Named modules the agent wished existed (with a one-line spec each), logged to
   * the dev wishlist. Emitted ONLY for chapter_created/chapter_updated runs.
   */
  missing_modules?: Array<{ name: string; spec: string }>;
  reasoning?: string;
}

export interface AgentResult {
  brief: BriefOutput | null;
  trace: AgentTraceEntry[];
  raw: string;
  error?: string;
}

/** Options for the full tool-use agent loop. */
export interface RunAgentLoopOptions {
  /** The opening user context describing what to prepare. */
  context: string;
  /** System prompt (cached as the stable prefix). */
  system: string;
  /** The toolset (sorted + cached by the gateway). */
  tools: ToolDef[];
  /** Async tool dispatcher: name + input → JSON-serializable result. */
  handleTool: (name: string, input: Record<string, unknown>) => Promise<unknown>;
  /** Per-user budget context. */
  ctx: GatewayContext;
  /** Override turn ceiling (defaults to MAX_TURNS=12). */
  maxTurns?: number;
  /** Override max_tokens per turn. */
  maxTokens?: number;
}

// ─────────────────────────── header / usage helpers ───────────────────────────

/** Read the anthropic-ratelimit-*-limit headers off a raw Response. */
function readReportedLimits(res: Response): ReportedLimits {
  const num = (name: string): number | undefined => {
    const v = res.headers.get(name);
    if (v == null) return undefined;
    const n = Number(v);
    return Number.isFinite(n) ? n : undefined;
  };
  return {
    requests: num("anthropic-ratelimit-requests-limit"),
    inputTokens: num("anthropic-ratelimit-input-tokens-limit"),
    outputTokens: num("anthropic-ratelimit-output-tokens-limit"),
  };
}

/** Parse Retry-After (seconds or HTTP-date) into an absolute epoch-ms, if present. */
function retryAfterUntilMs(headers: Headers | undefined): number | null {
  const v = headers?.get?.("retry-after");
  if (!v) return null;
  const secs = Number(v);
  if (Number.isFinite(secs)) return Date.now() + secs * 1000;
  const date = Date.parse(v);
  return Number.isFinite(date) ? date : null;
}

/** Pull headers off whatever an APIError exposes (SDK shape varies by version). */
function errorHeaders(err: APIError): Headers | undefined {
  const h = (err as unknown as { headers?: unknown }).headers;
  if (h instanceof Headers) return h;
  if (h && typeof (h as Headers).get === "function") return h as Headers;
  return undefined;
}

/** A 429 with remaining≈0 is token exhaustion (pause the bucket to reset time). */
function isTokenExhaustion(err: APIError): boolean {
  const h = errorHeaders(err);
  if (!h) return false;
  const rem = [
    h.get("anthropic-ratelimit-requests-remaining"),
    h.get("anthropic-ratelimit-input-tokens-remaining"),
    h.get("anthropic-ratelimit-output-tokens-remaining"),
  ];
  return rem.some((r) => r != null && Number(r) <= 0);
}

/** Is this a non-self-healing failure that should trip the circuit breaker? */
function isCircuitTripper(err: APIError): boolean {
  if (err.status === 401 || err.status === 403) return true;
  // 400 billing/credit errors won't fix themselves either.
  if (err.status === 400) {
    const type = (err as unknown as { error?: { type?: string } }).error?.type ?? "";
    const msg = (err.message ?? "").toLowerCase();
    return type === "billing_error" || msg.includes("credit") || msg.includes("billing");
  }
  return false;
}

/**
 * Estimate uncached input tokens for the NEW turn(s) only. On the first
 * (cache-write) turn we reserve the full prefix; on later turns the prefix is
 * cache_read (free for ITPM), so we estimate just the newly-appended content —
 * otherwise a 12-turn loop over-reserves the cached prefix on every turn and
 * self-throttles below the real ceiling (§4.b).
 */
export function estimateInputTokens(text: string): number {
  return Math.max(1, Math.ceil(text.length / CHARS_PER_TOKEN));
}

/** Rough char count of a MessageParam's content (for the new-turn estimate). */
function messageChars(m: Anthropic.MessageParam): number {
  if (typeof m.content === "string") return m.content.length;
  let n = 0;
  for (const block of m.content) {
    if ("text" in block && typeof block.text === "string") n += block.text.length;
    else n += JSON.stringify(block).length;
  }
  return n;
}

// ─────────────────────────── prompt-cache prefix builders ───────────────────────────

/** Build a cached system content block (ttl 1h on the stable prefix). */
function buildSystem(system: string): Anthropic.TextBlockParam[] {
  return [
    {
      type: "text",
      text: system,
      // cast: ttl typing varies by SDK version; the wire accepts ttl:"1h".
      cache_control: CACHE_1H as unknown as Anthropic.TextBlockParam["cache_control"],
    },
  ];
}

/**
 * Sort tools by name and put cache_control on the LAST tool — a byte-stable
 * prefix so tools+system cache together. Returns undefined for no tools.
 */
function buildTools(tools: ToolDef[] | undefined): Anthropic.Tool[] | undefined {
  if (!tools || tools.length === 0) return undefined;
  const sorted = [...tools].sort((a, b) => a.name.localeCompare(b.name));
  return sorted.map((t, i) => {
    const tool = {
      name: t.name,
      description: t.description,
      input_schema: t.input_schema,
    } as unknown as Anthropic.Tool;
    if (i === sorted.length - 1) {
      (tool as unknown as { cache_control: unknown }).cache_control = CACHE_1H;
    }
    return tool;
  });
}

/** Assert the agent prefix carries cache_control — a launch blocker (§4.b). */
export function assertCacheEnabled(system: string, tools: ToolDef[]): void {
  const sys = buildSystem(system);
  const builtTools = buildTools(tools);
  const sysCached = sys[0]?.cache_control != null;
  const lastTool = builtTools?.[builtTools.length - 1] as unknown as { cache_control?: unknown };
  const toolsCached = builtTools == null || lastTool?.cache_control != null;
  if (!sysCached || !toolsCached) {
    throw new Error(
      "Gateway launch blocker: agent prefix is missing cache_control. " +
        "A Tier-1 12-turn loop is near-unviable without the prompt cache.",
    );
  }
}

// ─────────────────────────── the throttled send ───────────────────────────

/** A single throttled, reconciled, retried call to messages.create. */
async function send(
  route: Route,
  params: Anthropic.MessageCreateParamsNonStreaming,
  estInput: number,
  reserveOutput: number,
  ctx: GatewayContext,
): Promise<Anthropic.Message> {
  if (pool.isCircuitOpen()) throw new CircuitOpenError(Date.now() + CIRCUIT.cooldownMs);
  // Refuse before spending if the user is already over their daily budget.
  if (isOverDailyBudget(ctx.userId)) throw new BudgetExceededError(ctx.userId);

  let lastErr: unknown;
  for (let attempt = 0; attempt <= RETRY.retryMax; attempt++) {
    // Re-acquire a fresh reservation on each attempt (a failed attempt aborts its own).
    const reservation: Reservation = await pool.acquire(route, estInput, reserveOutput);
    try {
      // `.withResponse()` exposes the raw Response so we can read rate-limit headers.
      const { data, response } = await client.messages
        .create(params)
        .withResponse();

      // Self-clamp every bucket to min(configured, server-reported) on EVERY response.
      pool.clampFromHeaders(route, readReportedLimits(response));

      const usage = toChargeable(data.usage);
      reservation.settle(usage);
      // Budget ledger: input + cache_creation + output (cache_read excluded).
      chargeUsageLedger(ctx.userId, usage);
      return data;
    } catch (err) {
      reservation.abort();
      lastErr = err;

      if (err instanceof APIError) {
        // 401/403/credit → trip the breaker and fail fast (won't self-heal).
        if (isCircuitTripper(err)) {
          pool.tripCircuit(CIRCUIT.cooldownMs);
          throw err;
        }
        const headers = errorHeaders(err);
        const retryAfter = retryAfterUntilMs(headers);

        if (err.status === 429) {
          if (isTokenExhaustion(err)) {
            // Pause the WHOLE bucket until reset; honor Retry-After if given.
            const until = retryAfter ?? Date.now() + backoffDelayMs(attempt);
            pool.pauseUntil(route, until);
          } else {
            // Acceleration limit: reduce admission for a cooldown (don't hard-pause).
            pool.reduceAdmission(route, ACCEL_COOLDOWN_MS);
            await sleep(retryAfter ? Math.max(0, retryAfter - Date.now()) : backoffDelayMs(attempt));
          }
          continue;
        }
        if (err.status === 529 || (err.status != null && err.status >= 500)) {
          // 529 Overloaded / 5xx: per-request jittered backoff; do NOT pause the
          // shared bucket (it's an availability decision, not a rate decision).
          await sleep(retryAfter ? Math.max(0, retryAfter - Date.now()) : backoffDelayMs(attempt));
          continue;
        }
        // Other 4xx (e.g. 400 validation) are non-transient — fail immediately.
        throw err;
      }
      // Network / unknown error: jittered backoff and retry.
      await sleep(backoffDelayMs(attempt));
    }
  }
  throw lastErr ?? new Error("gateway: exhausted retries");
}

/** Narrow the SDK usage object to the fields buckets + ledger need. */
function toChargeable(usage: Anthropic.Usage): ChargeableUsage {
  const u = usage as unknown as {
    input_tokens: number;
    output_tokens: number;
    cache_creation_input_tokens?: number | null;
    cache_read_input_tokens?: number | null;
  };
  return {
    input_tokens: u.input_tokens ?? 0,
    output_tokens: u.output_tokens ?? 0,
    cache_creation_input_tokens: u.cache_creation_input_tokens ?? 0,
    cache_read_input_tokens: u.cache_read_input_tokens ?? 0,
  };
}

// ─────────────────────────── public: createMessage ───────────────────────────

/**
 * Throttled 1:1 wrapper around messages.create. Picks the model from `route`,
 * caches the system + sorted tools, reserves/reconciles all three buckets, and
 * honors Retry-After / 529 / circuit-breaker. The single entry point for
 * one-shot calls (e.g. ai.ask via the worker's one_shot drain).
 */
export async function createMessage(
  req: GatewayRequest,
  ctx: GatewayContext,
): Promise<Anthropic.Message> {
  const cfg = ROUTES[req.route];
  if (!apiKey) {
    throw new Error(
      "ANTHROPIC_API_KEY is not set — the gateway has no key to call Anthropic with.",
    );
  }
  const maxTokens = req.maxTokens ?? cfg.maxTokens;
  const tools = buildTools(req.tools);
  const params: Anthropic.MessageCreateParamsNonStreaming = {
    model: cfg.model,
    max_tokens: maxTokens,
    system: req.system ? buildSystem(req.system) : undefined,
    tools,
    messages: req.messages,
  };
  // Estimate uncached input over the whole prompt. A one-shot call has no
  // pre-warmed cached prefix, so we reserve system + tools + all messages.
  const promptChars =
    (req.system?.length ?? 0) +
    (req.tools ? JSON.stringify(req.tools).length : 0) +
    req.messages.reduce((n, m) => n + messageChars(m), 0);
  const estInput = Math.max(1, Math.ceil(promptChars / CHARS_PER_TOKEN));
  return send(req.route, params, estInput, maxTokens, ctx);
}

// ─────────────────────────── public: runAgentLoop ───────────────────────────

/**
 * The agent tool-use loop, INSIDE the gateway. Each turn is a fully-throttled
 * `send()` — so a single daily_scan fanning out to up to 12 sequential Sonnet
 * calls is bounded by the buckets on EVERY turn, not just the entry.
 *
 * Caching: system + name-sorted tools form a byte-stable cached prefix (ttl 1h);
 * the conversation grows turn by turn, so the prefix is cache_read (free ITPM)
 * after the first turn. We reserve the full prefix once (turn 1, the cache-write)
 * and only the new turn's tokens thereafter.
 */
export async function runAgentLoop(opts: RunAgentLoopOptions): Promise<AgentResult> {
  const route: Route = "agent";
  const cfg = ROUTES[route];
  const trace: AgentTraceEntry[] = [];

  if (!apiKey) return stubFallback(opts.context, trace);

  // Launch-blocker assertion: the agent prefix must be cacheable.
  assertCacheEnabled(opts.system, opts.tools);

  const system = buildSystem(opts.system);
  const tools = buildTools(opts.tools);
  const maxTokens = opts.maxTokens ?? cfg.maxTokens;
  const maxTurns = opts.maxTurns ?? MAX_TURNS;

  const messages: Anthropic.MessageParam[] = [{ role: "user", content: opts.context }];
  // Full prefix estimate (system + tools + opening user turn), reserved ONCE on
  // the first cache-write turn. After that the prefix is a free cache_read, so
  // we only reserve the newly-appended turn — otherwise a 12-turn loop
  // over-reserves the cached prefix every turn and self-throttles (§4.b).
  const firstTurnEst = estimateInputTokens(
    opts.system + JSON.stringify(opts.tools) + opts.context,
  );

  let turn = 0;
  while (turn < maxTurns) {
    turn++;
    const estInput =
      turn === 1
        ? firstTurnEst
        : Math.max(1, Math.ceil(messageChars(messages[messages.length - 1]) / CHARS_PER_TOKEN));

    const params: Anthropic.MessageCreateParamsNonStreaming = {
      model: cfg.model,
      max_tokens: maxTokens,
      system,
      tools,
      messages,
    };

    let response: Anthropic.Message;
    try {
      response = await send(route, params, Math.max(1, estInput), maxTokens, opts.ctx);
    } catch (err) {
      // `send()` already exhausted its internal 429/5xx/network retries (or hit a
      // hard failure). A circuit-tripper (401/403/billing) or budget exhaustion
      // won't heal on a queue retry; everything else `send` throws here is a
      // transient send-exhaustion the queue should retry via MAX_ATTEMPTS.
      const message = `agent send failed: ${(err as Error).message}`;
      if (err instanceof BudgetExceededError || isCircuitTripper(err as APIError)) {
        throw new NonTransientAgentError(message);
      }
      throw new TransientAgentError(message, { cause: err });
    }

    const toolUses: Anthropic.ToolUseBlock[] = [];
    for (const block of response.content) {
      if (block.type === "text") {
        trace.push({ turn, kind: "model_text", payload: block.text });
      } else if (block.type === "tool_use") {
        toolUses.push(block);
        trace.push({ turn, kind: "tool_use", payload: { name: block.name, input: block.input, id: block.id } });
      }
    }

    // No tool calls → the model returned its final brief JSON.
    if (response.stop_reason !== "tool_use" || toolUses.length === 0) {
      const finalText = response.content
        .filter((b): b is Anthropic.TextBlock => b.type === "text")
        .map((b) => b.text)
        .join("\n")
        .trim();
      return parseFinal(finalText, trace);
    }

    // Run each tool and feed results back.
    const toolResults: Anthropic.ToolResultBlockParam[] = [];
    for (const use of toolUses) {
      let result: unknown;
      try {
        result = await opts.handleTool(use.name, use.input as Record<string, unknown>);
      } catch (err) {
        result = { error: (err as Error).message };
      }
      trace.push({ turn, kind: "tool_result", payload: { tool_use_id: use.id, result } });
      toolResults.push({
        type: "tool_result",
        tool_use_id: use.id,
        content: JSON.stringify(result).slice(0, 12_000),
      });
    }

    messages.push({ role: "assistant", content: response.content });
    messages.push({ role: "user", content: toolResults });
  }

  // Ran out of turns without a final brief — a deterministic ceiling, not a blip;
  // a re-run would likely loop the same way, so fail the event immediately.
  throw new NonTransientAgentError(`exceeded max turns (${maxTurns})`);
}

// ─────────────────────────── public: prewarm ───────────────────────────

/**
 * Write the agent prefix into the cache at startup (a max_tokens:0 prefill).
 * Eliminates the cold-cache miss on the first real overnight turn. No-op without
 * a key. Failures are swallowed — prewarm is best-effort, never a boot blocker.
 */
export async function prewarm(system: string, tools: ToolDef[]): Promise<void> {
  if (!apiKey) return;
  assertCacheEnabled(system, tools);
  const params = {
    model: ROUTES.agent.model,
    max_tokens: 0,
    system: buildSystem(system),
    tools: buildTools(tools),
    messages: [{ role: "user", content: "warmup" }],
  } as unknown as Anthropic.MessageCreateParamsNonStreaming;
  try {
    const { response } = await client.messages.create(params).withResponse();
    pool.clampFromHeaders("agent", readReportedLimits(response));
  } catch {
    // best-effort
  }
}

// ─────────────────────────── final-JSON parse + stub ───────────────────────────

function parseFinal(raw: string, trace: AgentTraceEntry[]): AgentResult {
  let body = raw.trim();
  if (body.startsWith("```")) {
    body = body.replace(/^```(?:json)?\s*/i, "").replace(/```$/i, "").trim();
  }
  try {
    const parsed = JSON.parse(body) as BriefOutput;
    return { brief: parsed, trace, raw };
  } catch (err) {
    // Salvage pass: the model sometimes narrates before/after the JSON ("I have
    // everything I need… {…}"). The whole agent run is already paid for, so try
    // the outermost {...} span before declaring the run lost.
    const first = body.indexOf("{");
    const last = body.lastIndexOf("}");
    if (first !== -1 && last > first) {
      try {
        const parsed = JSON.parse(body.slice(first, last + 1)) as BriefOutput;
        trace.push({
          turn: -1,
          kind: "model_text",
          payload: `parseFinal: salvaged JSON embedded in prose (${first} chars of preamble)`,
        });
        return { brief: parsed, trace, raw };
      } catch {
        // fall through to the non-transient failure below
      }
    }
    // The model's final turn wasn't valid JSON — a re-run burns a full agent pass
    // and tends to fail the same way, so this is non-transient (fail immediately).
    throw new NonTransientAgentError(`failed to parse JSON: ${(err as Error).message}`);
  }
}

/** Deterministic offline brief when no API key is configured (dev parity). */
function stubFallback(context: string, trace: AgentTraceEntry[]): AgentResult {
  trace.push({ turn: 0, kind: "model_text", payload: "stub: no api key" });
  const brief: BriefOutput = {
    title: "Atlas is offline",
    situation: "ANTHROPIC_API_KEY is not set — the gateway is running in stub mode.",
    chapter_id: null,
    chapter_title: "System",
    relevance: "stub",
    when: "now",
    preview: "Set ANTHROPIC_API_KEY in the server env to enable real preparation.",
    structure: {
      sections: [
        {
          kind: "tactical",
          data: { text: `Context received: ${context.slice(0, 240)}${context.length > 240 ? "…" : ""}` },
        },
        { kind: "tactical", data: { text: "Add ANTHROPIC_API_KEY and restart the worker to see real briefs." } },
      ],
    },
    primary_action: "Add API key",
    secondary_actions: ["Dismiss"],
    proposals: [],
    watchers_to_create: [],
    // A morning turn in the agent's voice even offline — the verdict's subject is
    // the user's world (the night), never the gateway's process. One memo line, no
    // metrics theater. persist only writes this turn when opts.turnKind is set (a
    // daily scan), so it's inert on non-scan stub runs.
    day_memo: {
      verdict:
        "Offline tonight — nothing was prepared. Set *ANTHROPIC_API_KEY* and I'll work the next one.",
      // Voice rule holds even offline: the line's subject is the USER's world
      // (their data), never the agent's machinery ("the gateway is in stub mode").
      lines: [{ text: "Nothing was touched — your data sits exactly where you left it." }],
      source_tag: "stub",
    },
    reasoning: "Stub fallback engaged because no API key was found.",
  };
  return { brief, trace, raw: JSON.stringify(brief) };
}

/** Exposed for tests / diagnostics — the live bucket pool. */
export { pool as __bucketPool };

/** A fresh id for callers that need a correlation key. */
export const newRequestId = randomUUID;
