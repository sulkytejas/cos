/**
 * Brief structure schema — shared between the web app (renders briefs) and the
 * worker (generates them). The worker validates every brief it emits against
 * `BriefStructure` before writing; the renderer validates again on read and
 * falls back to plain text for unknown component names.
 *
 * Adding a new component requires:
 *   1. add a new entry to BriefSection (this file)
 *   2. add a matching React component under src/components/brief/
 *   3. register it in src/components/brief/BriefRenderer.tsx
 *   4. update the system prompt's "component catalogue" so Atlas knows it exists
 */

import { z } from "zod";

// ─── shared atoms ───────────────────────────────────────────────────

const TimelineItem = z.object({
  date: z.string(),
  text: z.string(),
  subtle: z.boolean().optional(),
});

const PredictionItem = z.object({
  text: z.string(),
  confidence: z.enum(["high", "medium", "low"]),
});

const MaterialItem = z.object({
  text: z.string(),
  ready: z.boolean(),
});

const OptionItem = z.object({
  label: z.string(),
  reasoning: z.string(),
  mark: z.enum(["recommended", "neutral"]).optional(),
});

const DiffItem = z.object({
  kind: z.enum(["added", "removed", "changed"]),
  text: z.string(),
});

const MutualConnection = z.object({
  name: z.string(),
  via: z.string(),
});

// ─── section component shapes ───────────────────────────────────────

export const PersonSection = z.object({
  kind: z.literal("person"),
  data: z.object({
    name: z.string(),
    role: z.string(),
    avatar: z.string(),
    facts: z.array(z.string()),
    mutual: z.array(MutualConnection).optional(),
  }),
});

export const TimelineSection = z.object({
  kind: z.literal("timeline"),
  data: z.object({
    title: z.string(),
    items: z.array(TimelineItem),
  }),
});

export const PredictionSection = z.object({
  kind: z.literal("prediction"),
  data: z.object({
    title: z.string(),
    items: z.array(PredictionItem),
  }),
});

export const MaterialsSection = z.object({
  kind: z.literal("materials"),
  data: z.object({
    title: z.string(),
    items: z.array(MaterialItem),
  }),
});

export const OptionsSection = z.object({
  kind: z.literal("options"),
  data: z.object({
    title: z.string(),
    items: z.array(OptionItem),
  }),
});

export const TacticalSection = z.object({
  kind: z.literal("tactical"),
  data: z.object({
    text: z.string(),
  }),
});

export const QuoteSection = z.object({
  kind: z.literal("quote"),
  data: z.object({
    text: z.string(),
    attribution: z.string(),
  }),
});

export const WatcherSection = z.object({
  kind: z.literal("watcher"),
  data: z.object({
    text: z.string(),
    cadence: z.string(),
    last: z.string().optional(),
  }),
});

export const DiffSection = z.object({
  kind: z.literal("diff"),
  data: z.object({
    title: z.string(),
    items: z.array(DiffItem),
  }),
});

// Action strip lives in the brief structure too, even though the screen renders
// it in a sticky footer. The worker decides primary/secondary; the renderer pins.
export const ActionSection = z.object({
  kind: z.literal("action"),
  data: z.object({
    primary: z.string(),
    secondary: z.array(z.string()).default([]),
  }),
});

export const BriefSection = z.discriminatedUnion("kind", [
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
]);

export type BriefSection = z.infer<typeof BriefSection>;
export const KnownSectionKinds = [
  "person",
  "timeline",
  "prediction",
  "materials",
  "options",
  "tactical",
  "quote",
  "watcher",
  "diff",
  "action",
] as const;

// ─── full brief structure ───────────────────────────────────────────

export const BriefStructure = z.object({
  sections: z.array(BriefSection),
});

export type BriefStructure = z.infer<typeof BriefStructure>;

/** Safe parse with fallback — used by the renderer. */
export function parseBriefStructure(raw: unknown):
  | { ok: true; value: BriefStructure }
  | { ok: false; error: string; unknownKinds: string[] } {
  const result = BriefStructure.safeParse(raw);
  if (result.success) return { ok: true, value: result.data };
  // If parse failed because of unknown kinds, surface them so we can log.
  const unknownKinds: string[] = [];
  if (
    raw &&
    typeof raw === "object" &&
    "sections" in raw &&
    Array.isArray((raw as { sections?: unknown }).sections)
  ) {
    for (const s of (raw as { sections: unknown[] }).sections) {
      if (s && typeof s === "object" && "kind" in s) {
        const k = (s as { kind: unknown }).kind;
        if (typeof k === "string" && !KnownSectionKinds.includes(k as never)) {
          unknownKinds.push(k);
        }
      }
    }
  }
  return { ok: false, error: result.error.message, unknownKinds };
}
