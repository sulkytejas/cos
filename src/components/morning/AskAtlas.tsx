"use client";
/**
 * AskAtlas — inline conversational panel under the Morning Page. Each Atlas
 * turn pushes { text:'', fullText: reply }; an interval grows text toward
 * fullText by 2 chars every 16ms. While streaming, a teal caret blinks at
 * the cursor. Asterisks become italic-teal spans via renderAtlasText.
 *
 * Replies come from POST /api/ask. If ANTHROPIC_API_KEY isn't set on the
 * server, the route returns a deterministic stub so the typing stream still
 * runs end-to-end in dev.
 */
import { useEffect, useRef, useState, Fragment } from "react";

interface Turn {
  role: "user" | "atlas";
  text: string;
  fullText: string;
}

export function AskAtlas({ context, onClose }: { context: string; onClose: () => void }) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [pending, setPending] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Stream the most recent Atlas turn character-by-character.
  useEffect(() => {
    const last = turns[turns.length - 1];
    if (!last || last.role !== "atlas" || last.text === last.fullText) return;
    const id = setInterval(() => {
      setTurns((prev) => {
        const idx = prev.length - 1;
        const t = prev[idx];
        if (!t || t.role !== "atlas" || t.text === t.fullText) {
          clearInterval(id);
          return prev;
        }
        const nextLen = Math.min(t.text.length + 2, t.fullText.length);
        const next = [...prev];
        next[idx] = { ...t, text: t.fullText.slice(0, nextLen) };
        return next;
      });
    }, 16);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [turns.length]);

  const send = async () => {
    const text = input.trim();
    if (!text || pending) return;
    setInput("");
    setTurns((prev) => [...prev, { role: "user", text, fullText: text }]);
    setPending(true);
    try {
      const res = await fetch("/api/ask", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          context,
          message: text,
          history: turns.map((t) => ({ role: t.role, text: t.fullText || t.text })),
        }),
      });
      const data = (await res.json()) as { reply: string };
      const cleaned = (data.reply || "").trim();
      setTurns((prev) => [...prev, { role: "atlas", text: "", fullText: cleaned }]);
    } catch {
      setTurns((prev) => [
        ...prev,
        { role: "atlas", text: "", fullText: "I lost the thread for a moment — try again?" },
      ]);
    }
    setPending(false);
  };

  return (
    <div
      style={{
        marginTop: 20,
        border: "1px solid var(--color-hairline)",
        borderRadius: 8,
        background: "var(--color-bg-elev)",
        overflow: "hidden",
        animation: "ask-rise 380ms cubic-bezier(.22,1,.36,1)",
      }}
    >
      <div
        style={{
          padding: "12px 14px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          borderBottom: "1px solid var(--color-hairline-soft)",
          background: "var(--color-bg-sunk)",
        }}
      >
        <div
          className="font-mono"
          style={{
            fontSize: 9,
            letterSpacing: "0.22em",
            textTransform: "uppercase",
            color: "var(--color-ink-3)",
          }}
        >
          Ask Atlas · anything about last night
        </div>
        <button
          onClick={onClose}
          className="pressable"
          style={{
            fontFamily: "var(--font-serif)",
            fontStyle: "italic",
            fontSize: 12.5,
            color: "var(--color-ink-3)",
            cursor: "pointer",
          }}
        >
          close
        </button>
      </div>

      <div
        style={{
          padding: "14px 16px 4px",
          display: "flex",
          flexDirection: "column",
          gap: 14,
        }}
      >
        {turns.length === 0 && !pending && (
          <div
            className="serif-i"
            style={{
              fontStyle: "italic",
              fontSize: 14,
              color: "var(--color-ink-3)",
              lineHeight: 1.5,
              textWrap: "pretty",
            }}
          >
            Anything you want to ask — what I noticed, what I skipped, why I wrote a line the way I did.
          </div>
        )}
        {turns.map((t, i) =>
          t.role === "user" ? (
            <div
              key={i}
              style={{
                alignSelf: "flex-end",
                maxWidth: "85%",
                padding: "8px 12px",
                borderRadius: 12,
                borderBottomRightRadius: 4,
                background: "var(--color-ink)",
                color: "#fff",
                fontFamily: "var(--font-sans)",
                fontSize: 13.5,
                lineHeight: 1.4,
              }}
            >
              {t.text}
            </div>
          ) : (
            <div
              key={i}
              style={{
                alignSelf: "flex-start",
                maxWidth: "92%",
                fontFamily: "var(--font-serif)",
                fontSize: 15.5,
                lineHeight: 1.5,
                color: "var(--color-ink)",
                textWrap: "pretty",
              }}
            >
              {renderAtlasText(t.text)}
              {t.text !== t.fullText && (
                <span
                  style={{
                    display: "inline-block",
                    width: 2,
                    height: 16,
                    background: "var(--color-teal)",
                    marginLeft: 2,
                    transform: "translateY(2px)",
                    animation: "blink 0.9s steps(2, start) infinite",
                  }}
                />
              )}
            </div>
          )
        )}
        {pending && (
          <div
            className="serif-i"
            style={{
              alignSelf: "flex-start",
              fontStyle: "italic",
              fontSize: 14,
              color: "var(--color-ink-3)",
              display: "flex",
              alignItems: "center",
              gap: 8,
            }}
          >
            <span
              style={{
                width: 5,
                height: 5,
                borderRadius: "50%",
                background: "var(--color-teal)",
                animation: "now-pulse 1.4s ease-in-out infinite",
              }}
            />
            thinking
          </div>
        )}
      </div>

      <div
        style={{
          padding: "10px 12px 12px",
          borderTop: "1px solid var(--color-hairline-soft)",
          display: "flex",
          alignItems: "flex-end",
          gap: 8,
        }}
      >
        <textarea
          ref={inputRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
          rows={1}
          placeholder="type or hold the mic…"
          style={{
            flex: 1,
            resize: "none",
            border: 0,
            outline: 0,
            fontFamily: "var(--font-sans)",
            fontSize: 14,
            lineHeight: 1.4,
            color: "var(--color-ink)",
            background: "transparent",
            maxHeight: 100,
          }}
        />
        <button
          onClick={send}
          disabled={!input.trim() || pending}
          className="pressable"
          style={{
            padding: "10px 14px",
            background:
              input.trim() && !pending ? "var(--color-teal-deep)" : "var(--color-bg-sunk)",
            color: input.trim() && !pending ? "#fff" : "var(--color-ink-4)",
            border: 0,
            borderRadius: 6,
            fontFamily: "var(--font-sans)",
            fontSize: 13,
            fontWeight: 500,
            letterSpacing: "0.01em",
            transition: "background 200ms",
            flexShrink: 0,
            cursor: input.trim() && !pending ? "pointer" : "default",
          }}
        >
          send
        </button>
      </div>
    </div>
  );
}

/** Renders Atlas's text with `*asterisk emphasis*` as italic-teal spans. */
function renderAtlasText(text: string) {
  const parts = text.split(/(\*[^*]+\*)/g);
  return parts.map((p, i) => {
    if (p.startsWith("*") && p.endsWith("*") && p.length > 2) {
      return (
        <em
          key={i}
          className="serif-i"
          style={{ fontStyle: "italic", color: "var(--color-teal-deep)" }}
        >
          {p.slice(1, -1)}
        </em>
      );
    }
    return <Fragment key={i}>{p}</Fragment>;
  });
}
