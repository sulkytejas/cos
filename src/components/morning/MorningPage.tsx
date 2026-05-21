"use client";
/**
 * Morning page — Atlas drafts one paragraph in your voice from the overnight
 * signals; you read it, strike lines that miss, optionally refine with a
 * tap, then Send to chapters to file the extracts. Hosts three animations:
 *   1. sentence-fly-to-chapters (dots fly from each sentence to the
 *      Chapters nav link on Send)
 *   2. AskAtlas typing-stream (Atlas's reply grows char-by-char)
 *   3. strike-settle (sentence rows shrink + dim when struck)
 *
 * Ported faithfully from atlas-screens.jsx (MorningPageScreen / MorningSentence
 * / AskAyumi / FlyingExtracts).
 */
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { trpc } from "@/lib/trpc";
import type { MorningPage as MorningPageData, MorningSentence as MSentence } from "@/lib/morning-page";
import { AskAtlas } from "./AskAtlas";

interface FlyingDot {
  id: string;
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  kind: "todo" | "decision" | "journal";
  delay: number;
}

export function MorningPage({ page }: { page: MorningPageData }) {
  const [struck, setStruck] = useState<Record<string, boolean>>({});
  const [refining, setRefining] = useState<string | null>(null);
  const [refineText, setRefineText] = useState<Record<string, string>>({});
  const [chatOpen, setChatOpen] = useState(false);
  const [done, setDone] = useState(false);
  const [flying, setFlying] = useState<FlyingDot[] | null>(null);

  const liveSentences = page.sentences.filter((s) => !struck[s.id]);
  const extractTotal = liveSentences.reduce<Record<string, number>>((acc, s) => {
    if (!s.extracts) return acc;
    for (const [k, v] of Object.entries(s.extracts)) {
      if (typeof v === "number") acc[k] = (acc[k] ?? 0) + v;
    }
    return acc;
  }, {});

  const counts = (["todo", "decision", "journal"] as const)
    .filter((k) => extractTotal[k])
    .map((k) =>
      k === "todo"
        ? `${extractTotal[k]} todo${extractTotal[k] === 1 ? "" : "s"}`
        : k === "decision"
        ? `${extractTotal[k]} decision${extractTotal[k] === 1 ? "" : "s"}`
        : `${extractTotal[k]} journal ${extractTotal[k] === 1 ? "note" : "notes"}`
    );

  const file = trpc.morning.filed.useMutation();

  const onSend = () => {
    if (done || flying) return;
    const chaptersBtn = document.querySelector<HTMLElement>('[data-tab="chapters"]');
    if (!chaptersBtn) {
      setDone(true);
      return;
    }
    const cr = chaptersBtn.getBoundingClientRect();
    const cx = cr.left + cr.width / 2;
    const cy = cr.top + cr.height / 2;

    const dots: FlyingDot[] = [];
    let stagger = 0;
    for (const s of page.sentences) {
      if (struck[s.id] || !s.extracts) continue;
      const el = document.querySelector<HTMLElement>(`[data-sentence-id="${s.id}"]`);
      if (!el) continue;
      const sr = el.getBoundingClientRect();
      let dotIndex = 0;
      for (const [kind, count] of Object.entries(s.extracts)) {
        if (typeof count !== "number") continue;
        for (let i = 0; i < count; i++) {
          dots.push({
            id: `${s.id}-${kind}-${i}`,
            fromX: sr.right - 18 - dotIndex * 12,
            fromY: sr.top + sr.height / 2,
            toX: cx + (Math.random() - 0.5) * 6,
            toY: cy,
            kind: kind as FlyingDot["kind"],
            delay: stagger,
          });
          stagger += 60;
          dotIndex++;
        }
      }
    }

    if (dots.length === 0) {
      setDone(true);
      return;
    }
    setFlying(dots);

    // Pulse the Chapters tab as the last dots arrive.
    const arrivalAt = Math.max(...dots.map((d) => d.delay)) + 540;
    setTimeout(() => {
      chaptersBtn.classList.add("chap-just-pulsed");
      setTimeout(() => chaptersBtn.classList.remove("chap-just-pulsed"), 1400);
    }, arrivalAt - 200);

    // After arrival, kick off the file mutation + settle into Filed.
    setTimeout(() => {
      file.mutate({
        sentences: page.sentences.map((s) => ({
          id: s.id,
          text: refineText[s.id] || s.text,
          chapter: s.chapter,
          extracts: struck[s.id] ? null : s.extracts,
        })),
      });
      setFlying(null);
      setDone(true);
    }, arrivalAt + 200);
  };

  return (
    <div className="pb-32">
      {/* Header */}
      <div className="pt-6 pb-2">
        <div
          className="font-mono"
          style={{
            fontSize: 9.5,
            letterSpacing: "0.22em",
            textTransform: "uppercase",
            color: "var(--color-ink-3)",
            marginBottom: 6,
          }}
        >
          {page.range} · drafted in your voice
        </div>
        <h1
          className="serif-i"
          style={{
            margin: 0,
            fontSize: 56,
            lineHeight: 0.96,
            fontStyle: "italic",
            color: "var(--color-ink)",
            letterSpacing: "-0.02em",
          }}
        >
          This morning
        </h1>
        <div
          className="serif-i"
          style={{
            marginTop: 14,
            fontStyle: "italic",
            fontSize: 14,
            color: "var(--color-ink-3)",
            lineHeight: 1.5,
            textWrap: "pretty",
          }}
        >
          Read it like rereading yourself. Swipe a line away if I got it wrong. Tap to nudge.
        </div>
      </div>

      <div style={{ height: 1, background: "var(--color-hairline)", margin: "20px 0 8px" }} />

      {/* Sentences */}
      <div>
        {page.sentences.map((s) => (
          <SentenceRow
            key={s.id}
            s={s}
            isStruck={!!struck[s.id]}
            isRefining={refining === s.id}
            override={refineText[s.id]}
            onStrike={() => setStruck((p) => ({ ...p, [s.id]: !p[s.id] }))}
            onUnstrike={() => setStruck((p) => ({ ...p, [s.id]: !p[s.id] }))}
            onTap={() => setRefining(refining === s.id ? null : s.id)}
            onRefineSubmit={(text) => {
              setRefineText((p) => ({ ...p, [s.id]: text }));
              setRefining(null);
            }}
            onRefineCancel={() => setRefining(null)}
          />
        ))}
      </div>

      {/* "If you keep this" summary */}
      {!done && (
        <div
          style={{
            margin: "24px 0 0",
            padding: "14px 0",
            borderTop: "1px solid var(--color-hairline)",
            borderBottom: "1px solid var(--color-hairline)",
          }}
        >
          <div
            className="font-mono"
            style={{
              fontSize: 9.5,
              letterSpacing: "0.18em",
              textTransform: "uppercase",
              color: "var(--color-ink-3)",
              marginBottom: 6,
            }}
          >
            If you keep this
          </div>
          <div
            className="serif-i"
            style={{
              fontStyle: "italic",
              fontSize: 14,
              color: "var(--color-ink-2)",
              lineHeight: 1.5,
            }}
          >
            {counts.length === 0 ? (
              <>Nothing will be filed — the page is empty.</>
            ) : (
              <>
                I'll quietly add{" "}
                <span style={{ color: "var(--color-teal-deep)" }}>
                  {counts.join(", ").replace(/, ([^,]*)$/, " and $1")}
                </span>{" "}
                to your chapters.
              </>
            )}
          </div>
        </div>
      )}

      {/* Actions */}
      {!done && (
        <div style={{ marginTop: 18, display: "flex", gap: 10 }}>
          <button
            onClick={onSend}
            className="pressable"
            disabled={flying !== null}
            style={{
              flex: 1,
              padding: 14,
              background: "var(--color-ink)",
              color: "#fff",
              border: 0,
              borderRadius: 6,
              fontFamily: "var(--font-sans)",
              fontWeight: 500,
              fontSize: 14,
              letterSpacing: "0.01em",
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 8,
              cursor: flying ? "default" : "pointer",
              opacity: flying ? 0.6 : 1,
            }}
          >
            <span>Send to chapters</span>
            <svg width="14" height="10" viewBox="0 0 14 10">
              <line x1="0" y1="5" x2="11" y2="5" stroke="#fff" strokeWidth="1" />
              <path d="M9 1 L13 5 L9 9" fill="none" stroke="#fff" strokeWidth="1" />
            </svg>
          </button>
          <button
            onClick={() => setChatOpen((v) => !v)}
            className="pressable"
            style={{
              padding: "14px 16px",
              border: "1px solid var(--color-hairline)",
              borderRadius: 6,
              background: chatOpen ? "var(--color-teal-soft)" : "transparent",
              fontFamily: "var(--font-serif)",
              fontStyle: "italic",
              fontSize: 14,
              color: chatOpen ? "var(--color-teal-deep)" : "var(--color-ink-2)",
              whiteSpace: "nowrap",
              transition: "all 200ms",
              cursor: "pointer",
            }}
          >
            Ask Atlas
          </button>
        </div>
      )}

      {/* Filed confirmation */}
      {done && (
        <div
          style={{
            marginTop: 24,
            padding: "16px 18px",
            border: "1px solid var(--color-forest)",
            borderRadius: 6,
            background: "var(--color-forest-soft)",
          }}
        >
          <div
            className="font-mono"
            style={{
              fontSize: 9.5,
              letterSpacing: "0.2em",
              textTransform: "uppercase",
              color: "var(--color-forest)",
              marginBottom: 8,
            }}
          >
            Filed
          </div>
          <div
            className="serif-i"
            style={{
              fontStyle: "italic",
              fontSize: 16,
              lineHeight: 1.45,
              color: "var(--color-ink)",
              textWrap: "pretty",
            }}
          >
            Your morning is in the chapters.
            {counts.length > 0 && (
              <> {counts.join(", ").replace(/, ([^,]*)$/, " and $1")}, all in place.</>
            )}{" "}
            <Link href="/" style={{ color: "var(--color-teal-deep)" }}>
              Back to Today →
            </Link>
          </div>
        </div>
      )}

      {/* Inline AskAtlas */}
      {chatOpen && (
        <AskAtlas
          context={pageToContext(page, struck, refineText)}
          onClose={() => setChatOpen(false)}
        />
      )}

      {/* Flying-extract dots overlay */}
      {flying && <FlyingExtracts dots={flying} />}
    </div>
  );
}

function pageToContext(
  page: MorningPageData,
  struck: Record<string, boolean>,
  refineText: Record<string, string>
): string {
  return page.sentences
    .filter((s) => !struck[s.id])
    .map((s) => refineText[s.id] || s.text)
    .join(" ");
}

// ─── FlyingExtracts ───────────────────────────────────────────────
// Fixed-position overlay of small dots that animate from sentence positions
// to the Chapters nav link. Two render phases: "start" places them at the
// from-positions invisibly; one rAF later they transition to to-positions.

function FlyingExtracts({ dots }: { dots: FlyingDot[] }) {
  const [phase, setPhase] = useState<"start" | "flying">("start");
  useEffect(() => {
    requestAnimationFrame(() => requestAnimationFrame(() => setPhase("flying")));
  }, []);
  const colorFor = (k: FlyingDot["kind"]) =>
    k === "todo" ? "var(--color-forest)" : k === "decision" ? "var(--color-teal)" : "var(--color-ink-2)";
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 999,
        pointerEvents: "none",
      }}
    >
      {dots.map((d) => {
        const x = phase === "start" ? d.fromX : d.toX;
        const y = phase === "start" ? d.fromY : d.toY;
        const opacity = phase === "start" ? 0 : 1;
        return (
          <div
            key={d.id}
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: 7,
              height: 7,
              borderRadius: "50%",
              background: colorFor(d.kind),
              transform: `translate(${x - 3.5}px, ${y - 3.5}px) scale(${
                phase === "start" ? 0.5 : 1
              })`,
              opacity,
              transition: `transform 620ms cubic-bezier(.55,0,.35,1) ${d.delay}ms, opacity 240ms ${d.delay}ms`,
              boxShadow: "0 0 0 2px rgba(255,255,255,0.85)",
            }}
          />
        );
      })}
    </div>
  );
}

// ─── SentenceRow ──────────────────────────────────────────────────
// Pointer-driven strike gesture. Drag-left strikes; drag-right (while struck)
// restores. Tap toggles the inline refine input. The strike-settle animation
// shrinks the row's padding + font-size with a 120ms delay so the strikethrough
// draws first and the row compresses second.

function SentenceRow({
  s,
  isStruck,
  isRefining,
  override,
  onStrike,
  onUnstrike,
  onTap,
  onRefineSubmit,
  onRefineCancel,
}: {
  s: MSentence;
  isStruck: boolean;
  isRefining: boolean;
  override?: string;
  onStrike: () => void;
  onUnstrike: () => void;
  onTap: () => void;
  onRefineSubmit: (text: string) => void;
  onRefineCancel: () => void;
}) {
  const [drag, setDrag] = useState(0);
  const [moved, setMoved] = useState(false);
  const startX = useRef<number | null>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const THRESHOLD = 100;

  useEffect(() => {
    if (isRefining) inputRef.current?.focus();
  }, [isRefining]);

  const onDown = (clientX: number) => {
    if (isRefining) return;
    startX.current = clientX;
    setMoved(false);
  };
  const onMove = (clientX: number) => {
    if (startX.current === null) return;
    const dx = clientX - startX.current;
    if (Math.abs(dx) > 4) setMoved(true);
    if (isStruck) {
      setDrag(Math.max(0, 1 - Math.max(0, dx) / THRESHOLD));
    } else {
      setDrag(Math.min(1, Math.max(0, -dx) / THRESHOLD));
    }
  };
  const onUp = () => {
    if (startX.current === null) return;
    startX.current = null;
    if (!moved) {
      setDrag(isStruck ? 1 : 0);
      onTap();
      return;
    }
    if (isStruck) {
      if (drag < 0.5) onUnstrike();
    } else {
      if (drag > 0.5) onStrike();
    }
    setMoved(false);
    setTimeout(() => setDrag(0), 0);
  };

  const dragging = startX.current !== null;
  const strikePct = dragging ? drag : isStruck ? 1 : 0;
  const displayText = override || s.text;

  return (
    <div
      onMouseDown={(e) => onDown(e.clientX)}
      onMouseMove={(e) => onMove(e.clientX)}
      onMouseUp={onUp}
      onMouseLeave={onUp}
      onTouchStart={(e) => onDown(e.touches[0].clientX)}
      onTouchMove={(e) => onMove(e.touches[0].clientX)}
      onTouchEnd={onUp}
      data-sentence-id={s.id}
      style={{
        padding: isStruck ? "5px 0" : "10px 0",
        cursor: isRefining ? "text" : "pointer",
        touchAction: "pan-y",
        userSelect: dragging ? "none" : "auto",
        position: "relative",
        borderBottom: "1px solid var(--color-hairline-soft)",
        transition: "padding 420ms cubic-bezier(.22,1,.36,1) 120ms",
      }}
    >
      <div
        style={{
          fontFamily: "var(--font-serif)",
          fontSize: isStruck ? 13 : 19,
          lineHeight: isStruck ? 1.35 : 1.42,
          color: isStruck ? "var(--color-ink-4)" : "var(--color-ink)",
          letterSpacing: "-0.003em",
          textWrap: "pretty",
          position: "relative",
          opacity: isStruck ? 0.7 : 1,
          transition:
            "color 320ms, font-size 420ms cubic-bezier(.22,1,.36,1) 120ms, line-height 420ms 120ms, opacity 420ms",
        }}
      >
        <span
          style={{
            backgroundImage:
              "linear-gradient(var(--color-ink-3), var(--color-ink-3))",
            backgroundSize: `${strikePct * 100}% 1.2px`,
            backgroundPosition: "0 60%",
            backgroundRepeat: "no-repeat",
            transition: dragging ? "none" : "background-size 380ms cubic-bezier(.22,1,.36,1)",
          }}
        >
          {displayText}
        </span>
        {override && (
          <span
            className="font-mono"
            style={{
              fontSize: 9,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "var(--color-teal-deep)",
              marginLeft: 8,
              verticalAlign: "middle",
            }}
          >
            edited
          </span>
        )}
      </div>

      {/* Swipe hint */}
      {dragging && drag > 0.2 && !isStruck && (
        <div
          style={{
            position: "absolute",
            right: 0,
            top: 12,
            fontFamily: "var(--font-mono)",
            fontSize: 9,
            letterSpacing: "0.16em",
            textTransform: "uppercase",
            color: drag > 0.5 ? "var(--color-teal-deep)" : "var(--color-ink-3)",
            opacity: Math.min(1, drag * 1.6),
            transition: "color 160ms",
            pointerEvents: "none",
          }}
        >
          {drag > 0.5 ? "release · strike" : "swipe left to strike"}
        </div>
      )}
      {dragging && drag < 0.8 && isStruck && (
        <div
          style={{
            position: "absolute",
            right: 0,
            top: 12,
            fontFamily: "var(--font-mono)",
            fontSize: 9,
            letterSpacing: "0.16em",
            textTransform: "uppercase",
            color: drag < 0.5 ? "var(--color-teal-deep)" : "var(--color-ink-3)",
            pointerEvents: "none",
          }}
        >
          {drag < 0.5 ? "release · restore" : "swipe right to restore"}
        </div>
      )}

      {/* Inline refine */}
      {isRefining && (
        <div
          style={{
            marginTop: 10,
            padding: "10px 12px",
            border: "1px solid var(--color-teal)",
            borderRadius: 4,
            background: "rgba(10, 111, 122, 0.03)",
          }}
          onClick={(e) => e.stopPropagation()}
          onMouseDown={(e) => e.stopPropagation()}
        >
          <div
            className="font-mono"
            style={{
              fontSize: 9,
              letterSpacing: "0.2em",
              textTransform: "uppercase",
              color: "var(--color-teal-deep)",
              marginBottom: 6,
            }}
          >
            nudge atlas
          </div>
          <textarea
            ref={inputRef}
            defaultValue={override || ""}
            placeholder="say it differently…"
            rows={2}
            style={{
              width: "100%",
              resize: "none",
              border: 0,
              outline: 0,
              fontFamily: "var(--font-serif)",
              fontStyle: "italic",
              fontSize: 15,
              lineHeight: 1.45,
              color: "var(--color-ink)",
              background: "transparent",
            }}
          />
          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: 8,
              marginTop: 6,
            }}
          >
            <button
              onClick={(e) => {
                e.stopPropagation();
                onRefineCancel();
              }}
              className="pressable"
              style={{
                padding: "6px 10px",
                fontFamily: "var(--font-serif)",
                fontStyle: "italic",
                fontSize: 12.5,
                color: "var(--color-ink-3)",
                cursor: "pointer",
              }}
            >
              cancel
            </button>
            <button
              onClick={(e) => {
                e.stopPropagation();
                const v = inputRef.current?.value.trim();
                if (v) onRefineSubmit(v);
                else onRefineCancel();
              }}
              className="pressable"
              style={{
                padding: "6px 12px",
                borderRadius: 4,
                background: "var(--color-teal-deep)",
                color: "#fff",
                fontFamily: "var(--font-sans)",
                fontSize: 12.5,
                fontWeight: 500,
                cursor: "pointer",
              }}
            >
              use this
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
