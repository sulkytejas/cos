/**
 * Morning page seed — Atlas drafts one paragraph in your voice each
 * morning, sourced from overnight signals. v0.2 ships this as a static
 * record exposed via tRPC; v0.3 replaces it with the daily-scan output
 * the worker writes into a `morning_pages` table.
 *
 * The shape mirrors atlas-v2-data.jsx's ATLAS_MORNING_PAGE exactly.
 */

export type MorningSentence = {
  id: string;
  text: string;
  /** chapter id the extracts would land in (matches chapters.id) */
  chapter: string | null;
  /** per-kind extract counts */
  extracts: {
    todo?: number;
    decision?: number;
    journal?: number;
  } | null;
};

export type MorningPage = {
  range: string;     // "02:14 → 06:38"
  draftedAt: string; // "06:38"
  sentences: MorningSentence[];
};

/**
 * The morning page. Hand-authored placeholder — real worker output supersedes
 * this in v0.3. Chapter ids resolve at query time, so we use slug-style ids
 * here that map to chapter titles in the seed.
 */
export const SEEDED_MORNING_PAGE: MorningPage = {
  range: "02:14 → 06:38",
  draftedAt: "06:38",
  sentences: [
    {
      id: "s1",
      text: "It was a long night.",
      chapter: null,
      extracts: null,
    },
    {
      id: "s2",
      text: "Karan asked for retention numbers by Tuesday — added that to the list.",
      chapter: "Stratyfix",
      extracts: { todo: 1 },
    },
    {
      id: "s3",
      text: "Three small things for the trip: Volvo sleeper to Manali, offline maps for the valley, and cash past Kasol where the ATMs go sparse.",
      chapter: "Varanasi",
      extracts: { todo: 3 },
    },
    {
      id: "s4",
      text: "Trinity over UCD — I'd been holding that since April but only said it on yesterday's walk; the network argument tips the balance.",
      chapter: "Ireland",
      extracts: { decision: 1 },
    },
    {
      id: "s5",
      text: "Came back to \"irreversibility\" three times thinking about V.'s objections — that's the real worry, not the burn.",
      chapter: "Stratyfix",
      extracts: { journal: 1 },
    },
    {
      id: "s6",
      text: "The ARR slide is taking a lot of energy — 14 edits in a week. Noting it, though I'm unsure whether it's a signal or just the deck eating my Tuesdays.",
      chapter: "Stratyfix",
      extracts: { journal: 1 },
    },
  ],
};
