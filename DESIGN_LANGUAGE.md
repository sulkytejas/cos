# Raking Light — the Atlas design language

*Working name. Alternatives: Vellum, Almanac, Atlas Editorial.*

Atlas's interface language, the way Apple has Liquid Glass and Google has
Material. It is **not** a borrowed system — it's the one we'd never get from a
mass assistant (see [[PHILOSOPHY]]). One sentence:

> **Editorial type, set on paper, under one raking light — and never louder than it needs to be.**

Three ideas hold it together: *editorial* (type is the architecture),
*material* (surfaces are paper lit by a single light, not boxes with borders),
and *calm* (the UI informs from the periphery; it never performs). This document
is the contract; `Theme.swift` is the implementation.

---

## 1. Principles

1. **Type is the architecture.** Serif for voice, sans for body, mono for fact.
   Hierarchy comes from typeface and size, not from boxes.
2. **One light source.** Every surface is lit from the top-left (~30°). Depth is
   shadow and material, never an outline. *No container has a border.*
3. **Three materials, used with discipline.** Paper (A), vellum (B), pressed
   specimen (C). Most of the app is A; C appears at most once on a screen.
4. **Hairlines are rules, not frames.** A hairline may separate two rows or sit
   on interactive chrome (a button, a field, a chip). It may never outline a
   container.
5. **Calm over loud.** No exclamation, no badges-in-red, no performance.
   Information lives in the periphery and moves to the center only when it earns
   it. A line — *"Handled 23 newsletters overnight"* — is the product.
6. **Emphasis is italic serif, never bold.** Numbers and dates are always mono.

---

## 2. Light & material

One light, top-left. Separation is substance, not stroke.

| Material | Use | Treatment | Radius |
|---|---|---|---|
| **A — paper (raking light)** | default surface: cards, teasers, the capture well, the constellation map | white fill, soft directional shadow toward bottom-right, 1px top highlight, **no border** | `8` |
| **B — vellum** | supporting/quiet surfaces: tactical notes, callouts, reasoning popovers | translucent (page tone bleeds through), optional teal/forest tint, no outer shadow | `6` |
| **C — pressed specimen** | the *one* agentic ask (`AtlasNoticedCard`) | white, lifted higher than A with a longer asymmetric cast — visibly "resting on the page" | `8` |

The shadow is defined **once** (`RakingShadow` in `Theme.swift`) and shared by
`MaterialA` and `materialLift()`, so the entire light model is tuned in one
place. `.card()` resolves to Material A.

*Direction we own (not yet built):* make the light **physically real** — a
defined light position + a per-material BRDF, computing highlight/shadow instead
of hand-tuning. Liquid Glass fakes this; for three materials it's tractable.

---

## 3. Color

Warm paper, near-black ink, two accents. (Values live as named assets +
`Theme.Palette`.)

- **Surface** — paper/card `#ffffff`, sunk well `#f6f4ef`
- **Ink scale** — `#0d141a` · `#2c3942` · `#6a7480` · `#aab2bb`
- **Teal (primary)** — `#0089a8`, deep `#00576b`, soft `#e0f1f4`
- **Forest (secondary)** — `#0d3324`, soft `#e3ebe7`
- **Rules** — hairline `ink @ 10%`, soft `ink @ 6%`

*Adopt-before-the-big-guns:* author the scale in **OKLCH** for perceptual
uniformity, and verify contrast with **APCA / `Lc`** (not WCAG-2 `4.5:1`) — the
warm light-mode palette is exactly where the old ratio gives false fails.

---

## 4. Type

Three families, fixed roles. (`Theme.Font`.)

- **Instrument Serif** — titles & emphasis (italic). Display `72` (Today date),
  page title `46`, chapter masthead italic `36`, section heading `22`.
- **Manrope** — body `15`, muted `14`, label `13`.
- **JetBrains Mono** — all metadata, numbers, dates: meta-caps `10`, meta `11`.

Dates render `2026·05·27` (middle dot) or `today · 14:30`. *Adopt-before:*
variable-font **optical sizing** that adapts to context.

---

## 5. Space, radius, motion

- **Radius** — `4` chrome · `6` vellum · `8` paper/specimen.
- **Gutter** — `22` screen margin; `14–18` inside surfaces.
- **Motion** — tactile press is `scale 0.985`, `180ms ease-out`
  (`.pressable()` / `.pressScale`). Reveals stagger; nothing bounces. Calm.

---

## 6. The component contract (this is also a *generative-UI* contract)

Atlas's agent composes Briefs from a **fixed library** — the same pattern the
2025 research calls Generative UI. The agent emits structured JSON; the renderer
maps `kind → component`. New situations need *zero* new code.

**Brief sections (10):** `person` · `timeline` · `prediction` · `materials` ·
`options` · `tactical` (B) · `quote` · `watcher` (A) · `diff` · `action`.

**Shared primitives:** `ProvenanceDot` (● manual / ○ atlas / ◉ pending) ·
`SourcePill` · `BriefTeaserCard` (A) · `AtlasNoticedCard` (C) · `WatcherIcon`.

Rule: **compose, never invent.** A component not in the library falls back to a
`tactical` note — never a new shape.

---

## 7. What this language refuses

- It is not Material and not Liquid Glass. Adopting either would make Atlas look
  like everyone's product — the opposite of the point.
- No engagement mechanics, no ornament without information, no border drawn to
  "contain" something the light already separates.

When a screen feels uncertain, return to the sentence at the top.
