/**
 * POST /api/ask — short conversational reply from Atlas, used by AskAtlas
 * inside the Morning Page. Calls Anthropic directly (no tool-loop; this is
 * a one-shot chat, not an agentic run). Returns plain JSON { reply: string }.
 *
 * Falls back to a deterministic stub when ANTHROPIC_API_KEY is missing so
 * the typing-stream animation still runs end-to-end in dev.
 */
import Anthropic from "@anthropic-ai/sdk";
import { NextResponse } from "next/server";

const MODEL = "claude-sonnet-4-5";

interface HistoryTurn {
  role: "user" | "atlas";
  text: string;
}

export async function POST(req: Request) {
  const body = (await req.json()) as {
    context: string;
    message: string;
    history?: HistoryTurn[];
  };

  if (!body.message?.trim()) {
    return NextResponse.json({ reply: "" }, { status: 400 });
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return NextResponse.json({
      reply:
        "I'm running without a key right now — the typing stream is working but I don't have anything thoughtful to say. Add ANTHROPIC_API_KEY to *.env* and ask again.",
    });
  }

  const historyText = (body.history ?? [])
    .map((t) => `${t.role === "user" ? "User" : "Atlas"}: ${t.text}`)
    .join("\n");

  const userMessage = `You are Atlas, a quiet personal AI assistant. The user's morning page (drafted by you, in their voice, from overnight signals) reads:

"""
${body.context.slice(0, 4000)}
"""

Conversation so far:
${historyText || "(none)"}
User: ${body.message}

Reply as Atlas. Rules:
- 2-4 sentences. Quiet, conversational, no exclamation marks.
- Refer to the morning page when relevant.
- Never say "Great question" or anything performative.
- You may add italic-serif emphasis using *asterisks*.
- Sign nothing; just speak plainly.

Reply:`;

  try {
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 600,
      messages: [{ role: "user", content: userMessage }],
    });
    const text = response.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("\n")
      .trim();
    return NextResponse.json({ reply: text });
  } catch (err) {
    const message = (err as Error).message ?? "unknown error";
    return NextResponse.json({
      reply: `I lost the thread for a moment — *${message.slice(0, 120)}*. Try again?`,
    });
  }
}
