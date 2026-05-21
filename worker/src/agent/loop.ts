/**
 * The agentic loop. Takes a `context` string describing what Atlas should
 * prepare, runs an Anthropic conversation with the toolset until the model
 * returns a final text response (a JSON brief), parses it, and returns the
 * structured result + the trace.
 *
 * When ANTHROPIC_API_KEY is not set, the loop falls back to a deterministic
 * stub that emits a tiny "I would prepare a brief for: ..." response.
 * This keeps the worker functional in dev without a key.
 */
import Anthropic from "@anthropic-ai/sdk";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { TOOL_SCHEMAS, handleTool } from "../tools";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SYSTEM_PROMPT_PATH = path.join(__dirname, "system-prompt.md");

const SYSTEM_PROMPT = fs.readFileSync(SYSTEM_PROMPT_PATH, "utf-8");
const MODEL = "claude-sonnet-4-5";   // adjust freely
const MAX_TURNS = 12;

export interface AgentResult {
  /** The structured brief JSON the model returned. May be null if parse failed. */
  brief: BriefOutput | null;
  trace: AgentTraceEntry[];
  /** Raw model output (last assistant message text), for debugging. */
  raw: string;
  error?: string;
}

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
  reasoning?: string;
}

export async function runAgent(context: string): Promise<AgentResult> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  const trace: AgentTraceEntry[] = [];

  if (!apiKey) {
    return stubFallback(context, trace);
  }

  const client = new Anthropic({ apiKey });

  const messages: Anthropic.MessageParam[] = [
    { role: "user", content: context },
  ];

  let turn = 0;
  while (turn < MAX_TURNS) {
    turn++;
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      // The SDK's tool typing is permissive about this shape.
      tools: TOOL_SCHEMAS as never,
      messages,
    });

    // Record the model's content
    const toolUses: Anthropic.ToolUseBlock[] = [];
    for (const block of response.content) {
      if (block.type === "text") {
        trace.push({ turn, kind: "model_text", payload: block.text });
      } else if (block.type === "tool_use") {
        toolUses.push(block);
        trace.push({
          turn,
          kind: "tool_use",
          payload: { name: block.name, input: block.input, id: block.id },
        });
      }
    }

    // If no tool_use blocks, we're done — extract the final text.
    if (response.stop_reason !== "tool_use" || toolUses.length === 0) {
      const finalText = response.content
        .filter((b): b is Anthropic.TextBlock => b.type === "text")
        .map((b) => b.text)
        .join("\n")
        .trim();
      return parseFinal(finalText, trace);
    }

    // Run each tool and feed the results back.
    const toolResults: Anthropic.ToolResultBlockParam[] = [];
    for (const use of toolUses) {
      let result: unknown;
      try {
        result = await handleTool(use.name, use.input as Record<string, unknown>);
      } catch (err) {
        result = { error: (err as Error).message };
      }
      trace.push({
        turn,
        kind: "tool_result",
        payload: { tool_use_id: use.id, result },
      });
      toolResults.push({
        type: "tool_result",
        tool_use_id: use.id,
        content: JSON.stringify(result).slice(0, 12000),
      });
    }

    messages.push({ role: "assistant", content: response.content });
    messages.push({ role: "user", content: toolResults });
  }

  return {
    brief: null,
    trace,
    raw: "",
    error: `exceeded max turns (${MAX_TURNS})`,
  };
}

function parseFinal(raw: string, trace: AgentTraceEntry[]): AgentResult {
  // Strip any markdown fence the model may emit.
  let body = raw.trim();
  if (body.startsWith("```")) {
    body = body.replace(/^```(?:json)?\s*/i, "").replace(/```$/i, "").trim();
  }
  try {
    const parsed = JSON.parse(body) as BriefOutput;
    return { brief: parsed, trace, raw };
  } catch (err) {
    return { brief: null, trace, raw, error: `failed to parse JSON: ${(err as Error).message}` };
  }
}

function stubFallback(context: string, trace: AgentTraceEntry[]): AgentResult {
  // Deterministic stub used when ANTHROPIC_API_KEY is missing. Emits a
  // minimal-but-valid brief so the pipeline still works end-to-end in dev.
  trace.push({ turn: 0, kind: "model_text", payload: "stub: no api key" });
  const brief: BriefOutput = {
    title: "Atlas is offline",
    situation: "ANTHROPIC_API_KEY is not set — the agent is running in stub mode.",
    chapter_id: null,
    chapter_title: "System",
    relevance: "stub",
    when: "now",
    preview: "Set ANTHROPIC_API_KEY in .env to enable real preparation.",
    structure: {
      sections: [
        {
          kind: "tactical",
          data: {
            text: `Context received: ${context.slice(0, 240)}${context.length > 240 ? "…" : ""}`,
          },
        },
        {
          kind: "tactical",
          data: { text: "Add ANTHROPIC_API_KEY to .env and restart the worker to see real briefs." },
        },
      ],
    },
    primary_action: "Add API key",
    secondary_actions: ["Dismiss"],
    proposals: [],
    watchers_to_create: [],
    reasoning: "Stub fallback engaged because no API key was found.",
  };
  return { brief, trace, raw: JSON.stringify(brief) };
}
