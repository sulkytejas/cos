"use client";
/**
 * Small primitives used outside the BriefRenderer: brief teaser cards
 * (Today's list), watcher lines, and the "Atlas noticed" inline nudge.
 */
import Link from "next/link";
import { WatcherIcon } from "./primitives";

export interface BriefTeaser {
  id: string;
  title: string;
  preview: string | null;
  chapterTitle?: string | null;
  when?: string | null;
  urgent?: boolean;
}

export function BriefTeaserCard({ brief }: { brief: BriefTeaser }) {
  return (
    <Link
      href={`/brief/${brief.id}`}
      className="pressable block"
      style={{
        padding: "14px 16px",
        border: "1px solid var(--color-hairline)",
        borderRadius: 6,
        background: "var(--color-bg-elev)",
        position: "relative",
        textDecoration: "none",
        color: "inherit",
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10, marginBottom: 6 }}>
        <div
          className="serif-i"
          style={{
            fontStyle: "italic",
            fontSize: 19,
            lineHeight: 1.18,
            color: "var(--color-ink)",
            letterSpacing: "-0.005em",
            flex: 1,
            textWrap: "balance",
          }}
        >
          {brief.title}
        </div>
        {brief.urgent && (
          <span className="pulse-dot" style={{ background: "var(--color-teal)", flexShrink: 0, marginTop: 5 }} />
        )}
      </div>
      {brief.preview && (
        <div style={{ fontSize: 13.5, lineHeight: 1.45, color: "var(--color-ink-2)", marginBottom: 10 }}>
          {brief.preview}
        </div>
      )}
      <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
        {brief.chapterTitle && (
          <span
            className="font-mono"
            style={{
              fontSize: 9.5,
              letterSpacing: "0.16em",
              textTransform: "uppercase",
              color: "var(--color-ink-3)",
            }}
          >
            {brief.chapterTitle}
          </span>
        )}
        {brief.chapterTitle && brief.when && <span style={{ color: "var(--color-ink-4)" }}>·</span>}
        {brief.when && (
          <span className="font-mono" style={{ fontSize: 9.5, color: "var(--color-ink-4)", letterSpacing: "0.06em" }}>
            {brief.when}
          </span>
        )}
      </div>
    </Link>
  );
}

export interface WatcherTeaser {
  id: string;
  description: string;
  cadenceLabel: string | null;
}

export function WatcherLine({ w }: { w: WatcherTeaser }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "baseline",
        gap: 10,
        padding: "10px 0",
        borderBottom: "1px solid var(--color-hairline-soft)",
      }}
    >
      <span style={{ transform: "translateY(2px)" }}>
        <WatcherIcon />
      </span>
      <span
        className="serif-i"
        style={{
          fontStyle: "italic",
          fontSize: 15,
          color: "var(--color-ink)",
          lineHeight: 1.35,
          flex: 1,
          textWrap: "balance",
        }}
      >
        {w.description}
      </span>
      <span
        className="font-mono"
        style={{
          fontSize: 9.5,
          color: "var(--color-ink-4)",
          letterSpacing: "0.1em",
          textTransform: "uppercase",
          whiteSpace: "nowrap",
          flexShrink: 0,
        }}
      >
        {w.cadenceLabel ?? ""}
      </span>
    </div>
  );
}
