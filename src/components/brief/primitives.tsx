/**
 * Shared primitives for v0.2 — used by Brief components and by various
 * screens. Keep this small; each piece earns its place.
 */
import React from "react";

export function SectionLabel({ text }: { text: string }) {
  return (
    <div
      className="font-mono"
      style={{
        fontSize: 9,
        letterSpacing: "0.22em",
        textTransform: "uppercase",
        color: "var(--color-ink-3)",
        marginBottom: 10,
      }}
    >
      {text}
    </div>
  );
}

/** Filled forest dot (manual) / hollow forest ring (atlas) / pulsing teal (pending). */
export function ProvenanceDot({ kind = "manual" }: { kind?: "manual" | "atlas" | "pending" }) {
  const isPending = kind === "pending";
  const isAtlas = kind === "atlas";
  return (
    <span
      aria-label={`provenance ${kind}`}
      style={{
        display: "inline-block",
        width: 7,
        height: 7,
        borderRadius: "50%",
        background: isAtlas
          ? "transparent"
          : isPending
          ? "var(--color-teal)"
          : "var(--color-forest)",
        border: isAtlas ? "1px solid var(--color-forest)" : "none",
        animation: isPending ? "prov-pulse 1.8s ease-in-out infinite" : "none",
        flexShrink: 0,
      }}
    />
  );
}

const SOURCE_COLORS: Record<string, string> = {
  Email: "var(--color-ink-2)",
  Calendar: "var(--color-teal-deep)",
  Voice: "var(--color-forest)",
  "Voice memo": "var(--color-forest)",
  Drive: "var(--color-ink-3)",
  Inferred: "var(--color-ink-3)",
  Manual: "var(--color-ink)",
};

export function SourcePill({ source, sub }: { source: string; sub?: string | null }) {
  const c = SOURCE_COLORS[source] ?? "var(--color-ink)";
  return (
    <span style={{ display: "inline-flex", alignItems: "baseline", gap: 6 }}>
      <span
        className="font-mono"
        style={{
          fontSize: 9.5,
          letterSpacing: "0.18em",
          textTransform: "uppercase",
          color: c,
        }}
      >
        {source}
      </span>
      {sub && (
        <span
          className="font-mono"
          style={{
            fontSize: 9.5,
            color: "var(--color-ink-4)",
            letterSpacing: "0.04em",
          }}
        >
          · {sub}
        </span>
      )}
    </span>
  );
}

export function WatcherIcon({
  size = 12,
  color = "var(--color-teal-deep)",
}: {
  size?: number;
  color?: string;
}) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" style={{ flexShrink: 0 }}>
      <circle cx="6" cy="6" r="5" fill="none" stroke={color} strokeWidth="0.7" />
      <circle cx="6" cy="6" r="2.6" fill="none" stroke={color} strokeWidth="0.7" />
      <circle cx="6" cy="6" r="0.9" fill={color} />
      <line x1="6" y1="1" x2="6" y2="2.4" stroke={color} strokeWidth="0.6" />
      <line x1="6" y1="9.6" x2="6" y2="11" stroke={color} strokeWidth="0.6" />
    </svg>
  );
}

export function Avatar({ text }: { text: string }) {
  return (
    <div
      style={{
        width: 44,
        height: 44,
        borderRadius: "50%",
        border: "1px solid var(--color-hairline)",
        background: "var(--color-bg-sunk)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: "var(--font-serif)",
        fontStyle: "italic",
        fontSize: 18,
        color: "var(--color-ink-2)",
        letterSpacing: "-0.02em",
        flexShrink: 0,
      }}
    >
      {text}
    </div>
  );
}

export const briefSectionStyle: React.CSSProperties = {
  padding: "18px 0",
  borderBottom: "1px solid var(--color-hairline-soft)",
};
