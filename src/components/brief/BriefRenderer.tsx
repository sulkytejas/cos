"use client";
/**
 * <BriefRenderer /> — takes a brief's `structure` JSON and instantiates the
 * matching components in order. Single source of truth for which sections
 * exist; new components must register here.
 *
 * Unknown component names render a FallbackSection (plain text dump) so the
 * page never blows up, and a tRPC mutation logs them into
 * `dev_unknown_components` so a dev can see what Atlas wanted that we
 * hadn't built yet.
 */

import { useEffect, type ReactElement } from "react";
import {
  parseBriefStructure,
  type BriefSection,
} from "@/lib/brief-schema";
import {
  PersonCard,
  TimelineBlock,
  PredictionBlock,
  MaterialsChecklist,
  OptionList,
  TacticalNote,
  QuoteCard,
  ActionStrip,
  WatcherCard,
  DiffBlock,
} from "./sections";
import { trpc } from "@/lib/trpc";

const REGISTRY: Record<BriefSection["kind"], (props: { data: never }) => ReactElement> = {
  person: PersonCard as never,
  timeline: TimelineBlock as never,
  prediction: PredictionBlock as never,
  materials: MaterialsChecklist as never,
  options: OptionList as never,
  tactical: TacticalNote as never,
  quote: QuoteCard as never,
  watcher: WatcherCard as never,
  diff: DiffBlock as never,
  action: ActionStrip as never,
};

export interface BriefRendererProps {
  briefId: string;
  structure: unknown;
  /** When true, log unknown component names to the dev table. */
  reportUnknown?: boolean;
}

export function BriefRenderer({ briefId, structure, reportUnknown = true }: BriefRendererProps) {
  const parsed = parseBriefStructure(structure);
  const logUnknown = trpc.brief.logUnknownComponent.useMutation();

  // If parse failed because of unknown kinds, report each one
  useEffect(() => {
    if (!reportUnknown) return;
    if (!parsed.ok) {
      for (const kind of parsed.unknownKinds) {
        logUnknown.mutate({ briefId, componentName: kind, rawProps: structure });
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [parsed.ok, briefId]);

  if (!parsed.ok) {
    // Best-effort: try to render *valid* sections, fallback others.
    const raw = (structure as { sections?: unknown })?.sections;
    if (!Array.isArray(raw)) {
      return <FallbackSection text="Atlas couldn't shape this brief — structure is malformed." />;
    }
    return (
      <>
        {raw.map((s, i) => <SafeSection key={i} raw={s} />)}
      </>
    );
  }

  return (
    <>
      {parsed.value.sections.map((s, i) => {
        const Cmp = REGISTRY[s.kind];
        return <Cmp key={i} data={s.data as never} />;
      })}
    </>
  );
}

function SafeSection({ raw }: { raw: unknown }) {
  if (raw && typeof raw === "object" && "kind" in raw) {
    const kind = (raw as { kind: unknown }).kind;
    if (typeof kind === "string" && kind in REGISTRY) {
      const Cmp = REGISTRY[kind as BriefSection["kind"]];
      const data = (raw as { data?: unknown }).data;
      try {
        return <Cmp data={data as never} />;
      } catch {
        return <FallbackSection text={`(${kind} section failed to render)`} />;
      }
    }
    return <FallbackSection text={`Atlas wanted a ${typeof kind === "string" ? kind : "?"} section that doesn't exist yet.`} />;
  }
  return <FallbackSection text="(malformed section)" />;
}

function FallbackSection({ text }: { text: string }) {
  return (
    <div
      style={{
        padding: "18px 0",
        borderBottom: "1px solid var(--color-hairline-soft)",
        fontFamily: "var(--font-serif)",
        fontStyle: "italic",
        fontSize: 14,
        color: "var(--color-ink-faint)",
      }}
    >
      {text}
    </div>
  );
}
