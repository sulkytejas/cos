/**
 * The agentic loop — now a thin adapter over THE AI GATEWAY.
 *
 * SERVER_ARCHITECTURE.md §4.b / Phase 0 "rewire": this file no longer calls
 * `messages.create` directly and no longer owns a turn loop. Both moved INSIDE
 * `src/server/anthropic/gateway.ts`, so every one of the up-to-MAX_TURNS Sonnet
 * calls a single `daily_scan` fans out into re-enters the triple token bucket —
 * not just the first call. The gateway also:
 *   - pins the model to `claude-sonnet-4-6` (via the `agent` route in config.ts),
 *   - sends `system` as a cache_control content block (ttl 1h),
 *   - sorts tools by name with cache_control on the last tool decl (byte-stable
 *     cached prefix), and asserts that prefix is cacheable (launch blocker).
 *
 * We keep this module's public surface (`runAgent`, `AgentResult`,
 * `AgentTraceEntry`, `BriefOutput`) so `persist.ts` / `processors/event.ts` are
 * unchanged. When ANTHROPIC_API_KEY is unset the gateway returns the same
 * deterministic stub brief, so the dev pipeline still works end-to-end.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { TOOL_SCHEMAS, handleTool } from "../tools";
import {
  runAgentLoop,
  type AgentResult,
  type AgentTraceEntry,
  type BriefOutput,
  type ToolDef,
} from "../../../src/server/anthropic/gateway";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SYSTEM_PROMPT_PATH = path.join(__dirname, "system-prompt.md");

const SYSTEM_PROMPT = fs.readFileSync(SYSTEM_PROMPT_PATH, "utf-8");

/**
 * Single-tenant bootstrap user for the per-user/day budget ledger. Auth +
 * a real `userId` column are Phase 2; until then every server-side agent run
 * is charged to one operator id (env-overridable). This is intentionally NOT a
 * fail-open default for *requests* — the gateway has no public entrypoint here;
 * it only labels the budget row.
 */
const BOOTSTRAP_USER_ID = process.env.ATLAS_USER_ID ?? "atlas-operator";

// Re-export the gateway's contract so existing importers (persist.ts) are
// unchanged — they still `import type { AgentResult, ... } from "./agent/loop"`.
export type { AgentResult, AgentTraceEntry, BriefOutput };

/** The worker's toolset in the gateway's `ToolDef` shape (sorted+cached there). */
const TOOLS: ToolDef[] = TOOL_SCHEMAS.map((t) => ({
  name: t.name,
  description: t.description,
  input_schema: t.input_schema as Record<string, unknown>,
}));

/** The system prompt + toolset the agent route runs with. Exported so the
 *  worker can prewarm / assert the cache prefix at startup. */
export function agentPrefix(): { system: string; tools: ToolDef[] } {
  return { system: SYSTEM_PROMPT, tools: TOOLS };
}

/**
 * Run the agent for a `context` string and return the structured brief + trace.
 * All throttling, prompt-caching, retries, Retry-After honoring, the per-user
 * budget, and the up-to-12-turn tool loop live in the gateway now.
 *
 * §4.d/§4.f: the run is charged to the owning `userId` (the event's emitter), so
 * the gateway's per-user/day budget ledger is keyed correctly. Falls back to the
 * single-tenant bootstrap operator when an explicit owner isn't supplied (e.g.
 * `worker/src/once.ts` dev runs).
 */
export async function runAgent(
  context: string,
  opts: { userId?: string } = {},
): Promise<AgentResult> {
  return runAgentLoop({
    context,
    system: SYSTEM_PROMPT,
    tools: TOOLS,
    handleTool: (name, input) => handleTool(name, input),
    ctx: { userId: opts.userId ?? BOOTSTRAP_USER_ID },
  });
}
