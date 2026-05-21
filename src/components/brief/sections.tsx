/**
 * The 10 brief sections, each consuming a typed `data` prop from
 * `src/lib/brief-schema.ts`. The visual vocabulary is unchanged from v0.1:
 * serif for emphasis, mono for metadata, hairline borders, restrained palette.
 */
"use client";

import { useState } from "react";
import { Avatar, SectionLabel, WatcherIcon, briefSectionStyle } from "./primitives";
import type { z } from "zod";
import type {
  PersonSection,
  TimelineSection,
  PredictionSection,
  MaterialsSection,
  OptionsSection,
  TacticalSection,
  QuoteSection,
  WatcherSection,
  DiffSection,
  ActionSection,
} from "@/lib/brief-schema";

type PersonData = z.infer<typeof PersonSection>["data"];
type TimelineData = z.infer<typeof TimelineSection>["data"];
type PredictionData = z.infer<typeof PredictionSection>["data"];
type MaterialsData = z.infer<typeof MaterialsSection>["data"];
type OptionsData = z.infer<typeof OptionsSection>["data"];
type TacticalData = z.infer<typeof TacticalSection>["data"];
type QuoteData = z.infer<typeof QuoteSection>["data"];
type WatcherData = z.infer<typeof WatcherSection>["data"];
type DiffData = z.infer<typeof DiffSection>["data"];
type ActionData = z.infer<typeof ActionSection>["data"];

// ─────────────────────── 1. PersonCard ───────────────────────

export function PersonCard({ data }: { data: PersonData }) {
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text="Person" />
      <div style={{ display: "flex", gap: 14, alignItems: "flex-start" }}>
        <Avatar text={data.avatar} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="font-serif" style={{ fontSize: 21, lineHeight: 1.15, color: "var(--color-ink)" }}>
            {data.name}
          </div>
          <div style={{ fontSize: 13, color: "var(--color-ink-3)", marginTop: 3 }}>
            {data.role}
          </div>
        </div>
      </div>
      <ul
        style={{
          margin: "14px 0 0",
          padding: 0,
          listStyle: "none",
          display: "flex",
          flexDirection: "column",
          gap: 7,
        }}
      >
        {data.facts.map((f, i) => (
          <li
            key={i}
            style={{
              display: "flex",
              alignItems: "baseline",
              gap: 8,
              fontSize: 13.5,
              lineHeight: 1.45,
              color: "var(--color-ink-2)",
            }}
          >
            <span
              style={{
                width: 3,
                height: 3,
                borderRadius: "50%",
                background: "var(--color-ink-3)",
                flexShrink: 0,
                transform: "translateY(-3px)",
              }}
            />
            <span style={{ flex: 1 }}>{f}</span>
          </li>
        ))}
      </ul>
      {data.mutual && data.mutual.length > 0 && (
        <div
          style={{
            marginTop: 14,
            paddingTop: 12,
            borderTop: "1px solid var(--color-hairline-soft)",
          }}
        >
          <div
            className="font-mono"
            style={{
              fontSize: 9,
              letterSpacing: "0.18em",
              textTransform: "uppercase",
              color: "var(--color-ink-3)",
              marginBottom: 8,
            }}
          >
            Mutual
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
            {data.mutual.map((m, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "baseline",
                  justifyContent: "space-between",
                  gap: 12,
                }}
              >
                <span className="font-serif" style={{ fontSize: 14, color: "var(--color-ink)", whiteSpace: "nowrap" }}>
                  {m.name}
                </span>
                <span
                  className="font-mono"
                  style={{
                    fontSize: 10,
                    color: "var(--color-ink-3)",
                    letterSpacing: "0.04em",
                    whiteSpace: "nowrap",
                  }}
                >
                  {m.via}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

// ─────────────────────── 2. TimelineSection ───────────────────────

export function TimelineBlock({ data }: { data: TimelineData }) {
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text={data.title} />
      <div style={{ position: "relative", paddingLeft: 18 }}>
        <div
          style={{
            position: "absolute",
            left: 4,
            top: 6,
            bottom: 6,
            width: 1,
            background: "var(--color-hairline)",
          }}
        />
        {data.items.map((it, i) => (
          <div
            key={i}
            style={{
              position: "relative",
              paddingBottom: i === data.items.length - 1 ? 0 : 14,
              opacity: it.subtle ? 0.55 : 1,
            }}
          >
            <span
              style={{
                position: "absolute",
                left: -18,
                top: 6,
                width: 9,
                height: 9,
                borderRadius: "50%",
                background: it.subtle ? "transparent" : "var(--color-bg-elev)",
                border: "1px solid var(--color-ink-3)",
              }}
            />
            <div
              className="font-mono"
              style={{
                fontSize: 10,
                letterSpacing: "0.08em",
                color: "var(--color-ink-3)",
                marginBottom: 3,
              }}
            >
              {it.date}
            </div>
            <div style={{ fontSize: 13.5, lineHeight: 1.45, color: "var(--color-ink-2)" }}>{it.text}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

// ─────────────────────── 3. PredictionBlock ───────────────────────

function ConfidenceGauge({ level }: { level: number }) {
  return (
    <div style={{ display: "flex", alignItems: "flex-end", gap: 1.5, paddingTop: 4 }}>
      {[1, 2, 3].map((n) => (
        <span
          key={n}
          style={{
            width: 2.5,
            height: 4 + (n - 1) * 3,
            background: n <= level ? "var(--color-teal)" : "var(--color-hairline)",
            borderRadius: 1,
          }}
        />
      ))}
    </div>
  );
}

export function PredictionBlock({ data }: { data: PredictionData }) {
  const fillLevel = { high: 3, medium: 2, low: 1 } as const;
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text={data.title} />
      <div style={{ display: "flex", flexDirection: "column" }}>
        {data.items.map((it, i) => (
          <div
            key={i}
            style={{
              display: "flex",
              alignItems: "flex-start",
              gap: 12,
              padding: "11px 0",
              borderBottom: i === data.items.length - 1 ? "none" : "1px solid var(--color-hairline-soft)",
            }}
          >
            <ConfidenceGauge level={fillLevel[it.confidence]} />
            <span style={{ flex: 1, fontSize: 13.5, lineHeight: 1.45, color: "var(--color-ink)" }}>
              {it.text}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

// ─────────────────────── 4. MaterialsChecklist ───────────────────────

function InkCheckbox({ checked, onToggle }: { checked: boolean; onToggle: () => void }) {
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-checked={checked}
      role="checkbox"
      style={{
        width: 18,
        height: 18,
        borderRadius: 4,
        border: `1px solid ${checked ? "var(--color-forest)" : "var(--color-border-warm-strong)"}`,
        background: checked ? "var(--color-forest)" : "transparent",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
        cursor: "pointer",
        transition: "background 180ms ease, border-color 180ms ease",
      }}
    >
      {checked && (
        <svg width="11" height="11" viewBox="0 0 14 14">
          <path
            d="M2.5 7.5 L5.6 10.5 L11.5 4.0"
            fill="none"
            stroke="#fff"
            strokeWidth="1.8"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      )}
    </button>
  );
}

export function MaterialsChecklist({ data }: { data: MaterialsData }) {
  const [items, setItems] = useState(data.items);
  const toggle = (i: number) =>
    setItems((arr) => arr.map((it, idx) => (idx === i ? { ...it, ready: !it.ready } : it)));
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text={data.title} />
      <div style={{ display: "flex", flexDirection: "column" }}>
        {items.map((it, i) => (
          <div
            key={i}
            onClick={() => toggle(i)}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10,
              padding: "9px 0",
              borderBottom: i === items.length - 1 ? "none" : "1px solid var(--color-hairline-soft)",
              cursor: "pointer",
            }}
          >
            <InkCheckbox checked={it.ready} onToggle={() => toggle(i)} />
            <span
              style={{
                flex: 1,
                fontSize: 13.5,
                lineHeight: 1.4,
                color: it.ready ? "var(--color-ink-3)" : "var(--color-ink)",
                textDecoration: it.ready ? "line-through" : "none",
                textDecorationColor: "var(--color-ink-4)",
                transition: "color 240ms",
              }}
            >
              {it.text}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

// ─────────────────────── 5. OptionList ───────────────────────

export function OptionList({ data }: { data: OptionsData }) {
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text={data.title} />
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        {data.items.map((it, i) => {
          const recommended = it.mark === "recommended";
          return (
            <div
              key={i}
              style={{
                paddingLeft: 14,
                borderLeft: `2px solid ${recommended ? "var(--color-teal)" : "var(--color-hairline)"}`,
              }}
            >
              <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 4 }}>
                <span
                  className="font-serif"
                  style={{
                    fontSize: 16,
                    color: "var(--color-ink)",
                    lineHeight: 1.2,
                    fontStyle: recommended ? "italic" : "normal",
                  }}
                >
                  {it.label}
                </span>
                {recommended && (
                  <span
                    className="font-mono"
                    style={{
                      fontSize: 9,
                      letterSpacing: "0.16em",
                      textTransform: "uppercase",
                      color: "var(--color-teal-deep)",
                    }}
                  >
                    · suggested
                  </span>
                )}
              </div>
              <div style={{ fontSize: 13, lineHeight: 1.5, color: "var(--color-ink-2)" }}>{it.reasoning}</div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

// ─────────────────────── 6. TacticalNote ───────────────────────

export function TacticalNote({ data }: { data: TacticalData }) {
  return (
    <section
      style={{
        background: "var(--color-bg-sunk)",
        borderRadius: 6,
        padding: "16px 18px",
        position: "relative",
        margin: "18px 0",
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 14,
          bottom: 14,
          width: 2,
          background: "var(--color-forest)",
          borderTopRightRadius: 2,
          borderBottomRightRadius: 2,
        }}
      />
      <div
        className="font-mono"
        style={{
          fontSize: 9,
          letterSpacing: "0.2em",
          textTransform: "uppercase",
          color: "var(--color-forest)",
          marginBottom: 8,
          paddingLeft: 4,
        }}
      >
        Tactical
      </div>
      <div
        className="serif-i"
        style={{
          fontStyle: "italic",
          fontSize: 16,
          lineHeight: 1.45,
          color: "var(--color-ink)",
          paddingLeft: 4,
          textWrap: "pretty",
        }}
      >
        {data.text}
      </div>
    </section>
  );
}

// ─────────────────────── 7. QuoteCard ───────────────────────

export function QuoteCard({ data }: { data: QuoteData }) {
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text="Quoted" />
      <div style={{ position: "relative", paddingLeft: 16 }}>
        <span
          style={{
            position: "absolute",
            left: -2,
            top: -8,
            fontFamily: "var(--font-serif)",
            fontStyle: "italic",
            fontSize: 52,
            lineHeight: 1,
            color: "var(--color-teal)",
            opacity: 0.45,
          }}
        >
          “
        </span>
        <div
          className="font-serif"
          style={{
            fontSize: 17,
            lineHeight: 1.45,
            color: "var(--color-ink)",
            textWrap: "pretty",
            letterSpacing: "-0.001em",
          }}
        >
          {data.text}
        </div>
        <div style={{ marginTop: 10, display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 14, height: 1, background: "var(--color-ink-3)" }} />
          <span
            className="font-mono"
            style={{ fontSize: 10, letterSpacing: "0.08em", color: "var(--color-ink-3)" }}
          >
            {data.attribution}
          </span>
        </div>
      </div>
    </section>
  );
}

// ─────────────────────── 8. ActionStrip ───────────────────────

export function ActionStrip({ data }: { data: ActionData }) {
  return (
    <div style={{ display: "flex", alignItems: "stretch", gap: 8 }}>
      <button
        className="pressable"
        style={{
          flex: 1,
          padding: "13px 14px",
          background: "var(--color-ink)",
          color: "#fff",
          border: 0,
          borderRadius: 4,
          fontFamily: "var(--font-sans)",
          fontWeight: 500,
          fontSize: 13.5,
          letterSpacing: "0.01em",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 8,
          cursor: "pointer",
        }}
      >
        <span>{data.primary}</span>
        <svg width="14" height="10" viewBox="0 0 14 10">
          <line x1="0" y1="5" x2="11" y2="5" stroke="#fff" strokeWidth="1" />
          <path d="M9 1 L13 5 L9 9" fill="none" stroke="#fff" strokeWidth="1" />
        </svg>
      </button>
      {(data.secondary ?? []).map((s, i) => (
        <button
          key={i}
          className="pressable"
          style={{
            padding: "11px 12px",
            minWidth: 0,
            background: "transparent",
            color: "var(--color-ink-2)",
            border: "1px solid var(--color-hairline)",
            borderRadius: 4,
            fontFamily: "var(--font-sans)",
            fontSize: 12,
            fontWeight: 500,
            whiteSpace: "nowrap",
            cursor: "pointer",
          }}
        >
          {s}
        </button>
      ))}
    </div>
  );
}

// ─────────────────────── 9. WatcherCard ───────────────────────

export function WatcherCard({ data }: { data: WatcherData }) {
  return (
    <section style={{ ...briefSectionStyle, padding: 0, border: 0, margin: "18px 0" }}>
      <div
        style={{
          display: "flex",
          alignItems: "flex-start",
          gap: 12,
          padding: "14px 16px",
          border: "1px solid var(--color-hairline)",
          borderRadius: 6,
          background: "var(--color-bg-elev)",
        }}
      >
        <div
          style={{
            width: 28,
            height: 28,
            borderRadius: "50%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            border: "1px solid var(--color-hairline)",
            flexShrink: 0,
          }}
        >
          <WatcherIcon size={14} />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            className="font-mono"
            style={{
              fontSize: 9,
              letterSpacing: "0.2em",
              textTransform: "uppercase",
              color: "var(--color-teal-deep)",
              marginBottom: 4,
            }}
          >
            Atlas is watching
          </div>
          <div
            className="serif-i"
            style={{
              fontStyle: "italic",
              fontSize: 16,
              lineHeight: 1.32,
              color: "var(--color-ink)",
              textWrap: "balance",
            }}
          >
            {data.text}
          </div>
          <div
            className="font-mono"
            style={{
              fontSize: 9.5,
              color: "var(--color-ink-4)",
              letterSpacing: "0.06em",
              marginTop: 6,
            }}
          >
            re-checks {data.cadence}
            {data.last ? ` · last ${data.last}` : ""}
          </div>
        </div>
      </div>
    </section>
  );
}

// ─────────────────────── 10. DiffBlock ───────────────────────

export function DiffBlock({ data }: { data: DiffData }) {
  const symbolFor = (k: "added" | "removed" | "changed") =>
    k === "added" ? "+" : k === "removed" ? "−" : "↺";
  const colorFor = (k: "added" | "removed" | "changed") =>
    k === "added" ? "var(--color-forest)" : k === "removed" ? "var(--color-ink-3)" : "var(--color-teal-deep)";
  return (
    <section style={briefSectionStyle}>
      <SectionLabel text={data.title} />
      <div style={{ display: "flex", flexDirection: "column" }}>
        {data.items.map((it, i) => (
          <div
            key={i}
            style={{
              display: "flex",
              gap: 12,
              padding: "9px 0",
              borderBottom: i === data.items.length - 1 ? "none" : "1px solid var(--color-hairline-soft)",
            }}
          >
            <span
              className="font-mono"
              style={{
                fontSize: 13,
                color: colorFor(it.kind),
                width: 12,
                flexShrink: 0,
                fontWeight: 500,
                lineHeight: 1.5,
              }}
            >
              {symbolFor(it.kind)}
            </span>
            <span
              style={{
                flex: 1,
                fontSize: 13.5,
                lineHeight: 1.5,
                color: it.kind === "removed" ? "var(--color-ink-3)" : "var(--color-ink)",
                textDecoration: it.kind === "removed" ? "line-through" : "none",
                textDecorationColor: "var(--color-ink-4)",
              }}
            >
              {it.text}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}
